import GRDB
import MealCore
import Observation

/// A list that loads in blocks: it holds the first rows of a query, keeps them current as the database
/// changes, and takes the next block when one of the last rows comes into view. A new query starts over
/// from the first block.
@MainActor @Observable
public final class PagedList<Query: Hashable & Sendable, Row: Identifiable & Hashable & Sendable> {
    public private(set) var rows: [Row] = []
    public private(set) var total = 0
    /// False until the first rows arrive, so an empty list is not shown as «nothing found» too early.
    public private(set) var isLoaded = false
    public private(set) var failure: String?
    /// Grows with every new query; a view scrolls back to the top when it changes.
    public private(set) var generation = 0

    public var query: Query {
        didSet {
            guard query != oldValue else { return }
            limit = pageSize
            generation += 1
            restart()
        }
    }

    public let pageSize: Int
    /// How close to the end a row must be to load the next block.
    public let prefetch: Int
    public private(set) var limit: Int

    @ObservationIgnored private let observe: (Query, Int) -> AsyncValueObservation<ListPage<Row>>
    @ObservationIgnored private var task: Task<Void, Never>?

    public init(
        query: Query, pageSize: Int = 100, prefetch: Int = 20,
        observe: @escaping (Query, Int) -> AsyncValueObservation<ListPage<Row>>
    ) {
        self.query = query
        self.pageSize = pageSize
        self.prefetch = prefetch
        self.limit = pageSize
        self.observe = observe
    }

    isolated deinit {
        task?.cancel()
    }

    public var isComplete: Bool {
        rows.count >= total
    }

    public func start() {
        if task == nil { restart() }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    /// Loads the next block when the row is among the last ones loaded and the list has more.
    public func rowAppeared(_ id: Row.ID) {
        guard rows.count >= limit, rows.count < total, rows.suffix(prefetch).contains(where: { $0.id == id }) else {
            return
        }
        limit += pageSize
        restart()
    }

    private func restart() {
        task?.cancel()
        let observation = observe(query, limit)
        task = Task { [weak self] in
            do {
                for try await page in observation {
                    guard let self else { return }
                    rows = page.rows
                    total = page.total
                    isLoaded = true
                    failure = nil
                }
            } catch is CancellationError {
            } catch {
                self?.failure = String(describing: error)
            }
        }
    }
}
