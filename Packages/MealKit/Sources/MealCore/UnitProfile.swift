/// What a product knows about its own units: the unit it is counted in, what one piece weighs, its density
/// and the weight of units only it can define, such as a clove or a bunch.
public struct UnitProfile: Hashable, Sendable {
    public var baseUnit: BaseUnit
    public var gramsPerPiece: Double?
    /// Grams per millilitre; for loose products, as they fill a spoon.
    public var density: Double?
    /// Grams of one named unit: a clove, a bunch, a can.
    public var namedUnits: [MeasureUnit: Double]

    public init(
        baseUnit: BaseUnit = .gram, gramsPerPiece: Double? = nil, density: Double? = nil,
        namedUnits: [MeasureUnit: Double] = [:]
    ) {
        self.baseUnit = baseUnit
        self.gramsPerPiece = gramsPerPiece
        self.density = density
        self.namedUnits = namedUnits
    }

    /// The amount in grams, or nil when the product cannot tell: a bunch it has no weight for.
    public func grams(_ amount: Double, _ unit: MeasureUnit) -> Double? {
        switch unit.kind {
        case .mass(let grams): amount * grams
        case .volume(let milliliters): density.map { amount * milliliters * $0 }
        case .piece: gramsPerPiece.map { amount * $0 }
        case .named: namedUnits[unit].map { amount * $0 }
        case .unmeasured: nil
        }
    }

    /// The amount in another unit: directly within mass or within volume, otherwise through grams.
    public func convert(_ amount: Double, from source: MeasureUnit, to target: MeasureUnit) -> Double? {
        if source == target { return amount }
        switch (source.kind, target.kind) {
        case (.mass(let from), .mass(let to)):
            return amount * from / to
        case (.volume(let from), .volume(let to)):
            return amount * from / to
        default:
            return grams(amount, source).flatMap { self.amount(ofGrams: $0, in: target) }
        }
    }

    /// The amount in the unit the product is kept in.
    public func inBaseUnit(_ amount: Double, _ unit: MeasureUnit) -> Double? {
        convert(amount, from: unit, to: baseUnit.unit)
    }

    private func amount(ofGrams grams: Double, in unit: MeasureUnit) -> Double? {
        let divisor: Double? =
            switch unit.kind {
            case .mass(let factor): factor
            case .volume(let milliliters): density.map { $0 * milliliters }
            case .piece: gramsPerPiece
            case .named: namedUnits[unit]
            case .unmeasured: nil
            }
        guard let divisor, divisor > 0 else { return nil }
        return grams / divisor
    }
}
