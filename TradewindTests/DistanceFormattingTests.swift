import Testing
import Foundation

@Suite("Distance formatting")
struct DistanceFormattingTests {

    let gb = Locale(identifier: "en_GB")
    let us = Locale(identifier: "en_US")

    @Test("Metric switches from metres to kilometres at a kilometre")
    func metricThresholds() {
        #expect(DistanceFormatting.readout(metres: 4.2, preference: .metric, locale: gb)
            == DistanceReadout(value: "4.2", unit: "m"))
        #expect(DistanceFormatting.readout(metres: 120, preference: .metric, locale: gb)
            == DistanceReadout(value: "120", unit: "m"))
        #expect(DistanceFormatting.readout(metres: 999, preference: .metric, locale: gb)
            == DistanceReadout(value: "999", unit: "m"))
        #expect(DistanceFormatting.readout(metres: 1_000, preference: .metric, locale: gb)
            == DistanceReadout(value: "1.0", unit: "km"))
        #expect(DistanceFormatting.readout(metres: 1_430, preference: .metric, locale: gb)
            == DistanceReadout(value: "1.4", unit: "km"))
        // Past ten kilometres the decimal stops earning its place.
        #expect(DistanceFormatting.readout(metres: 42_000, preference: .metric, locale: gb)
            == DistanceReadout(value: "42", unit: "km"))
    }

    @Test("Imperial switches from feet to miles")
    func imperialThresholds() {
        #expect(DistanceFormatting.readout(metres: 30, preference: .imperial, locale: us)
            == DistanceReadout(value: "98", unit: "ft"))
        // 1000 ft is the crossover.
        let justUnder = DistanceFormatting.readout(metres: 304, preference: .imperial, locale: us)
        #expect(justUnder.unit == "ft")
        let justOver = DistanceFormatting.readout(metres: 306, preference: .imperial, locale: us)
        #expect(justOver.unit == "mi")
        #expect(DistanceFormatting.readout(metres: 1_609.344, preference: .imperial, locale: us)
            == DistanceReadout(value: "1.0", unit: "mi"))
    }

    @Test("Automatic follows the locale's measurement system")
    func automaticFollowsLocale() {
        #expect(DistanceFormatting.usesImperial(preference: .automatic, locale: us))
        #expect(DistanceFormatting.usesImperial(preference: .automatic, locale: gb))
        #expect(!DistanceFormatting.usesImperial(
            preference: .automatic,
            locale: Locale(identifier: "de_DE")
        ))
        // An explicit preference always wins over the locale.
        #expect(!DistanceFormatting.usesImperial(preference: .metric, locale: us))
        #expect(DistanceFormatting.usesImperial(preference: .imperial, locale: gb))
    }

    @Test("Nonsense in, dash out")
    func invalidInput() {
        #expect(DistanceFormatting.readout(metres: .nan, preference: .metric).value == "—")
        #expect(DistanceFormatting.readout(metres: -5, preference: .metric).value == "—")
        #expect(DistanceFormatting.readout(metres: .infinity, preference: .metric).value == "—")
    }

    @Test("Walking time reads like a person talking")
    func walkingTime() {
        // Too close to be worth a number.
        #expect(DistanceFormatting.walkingTime(metres: 10) == nil)
        #expect(DistanceFormatting.walkingTime(metres: 400) == "5 min walk")
        #expect(DistanceFormatting.walkingTime(metres: 4_000) == "49 min walk")
        #expect(DistanceFormatting.walkingTime(metres: 8_000) == "1 h 38 min walk")
        // Beyond half a day on foot, "walk" is no longer advice.
        #expect(DistanceFormatting.walkingTime(metres: 300_000) == nil)
    }

    @Test("Elevation is signed and ignores noise")
    func elevation() {
        #expect(DistanceFormatting.elevationDelta(metres: 2, preference: .metric) == nil)
        #expect(DistanceFormatting.elevationDelta(metres: 48, preference: .metric)
            == "48 m above you")
        #expect(DistanceFormatting.elevationDelta(metres: -120, preference: .metric)
            == "120 m below you")
    }

    @Test("Compact form drops the space")
    func compact() {
        #expect(DistanceFormatting.compact(metres: 1_430, preference: .metric, locale: gb) == "1.4km")
        #expect(DistanceFormatting.compact(metres: 240, preference: .metric, locale: gb) == "240m")
    }
}
