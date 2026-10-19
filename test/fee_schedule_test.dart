import 'package:flutter_test/flutter_test.dart';
import 'package:ewa_app/models/fee_schedule.dart';

// The vectors below are the same ones functions/src/feeSchedule.test.ts uses, so
// the app's preview always matches what the server charges.
void main() {
  const tariff = FeeSchedule.tiered([
    FeeTier(upToMinor: 5000, flatMinor: 100),
    FeeTier(upToMinor: 20000, flatMinor: 300),
    FeeTier(upToMinor: 100000, flatMinor: 600, percent: 0.005),
    FeeTier(upToMinor: null, percent: 0.015),
  ]);
  const capped = FeeSchedule.tiered([FeeTier(upToMinor: 50000, flatMinor: 200)]);

  test('percent mode rounds to a cent', () {
    expect(const FeeSchedule.percent(0.05).feeMinorFor(20000), 1000);
    expect(const FeeSchedule.percent(0.05).feeMinorFor(3333), 167);
    expect(const FeeSchedule.percent(0).feeMinorFor(5000), 0);
  });

  test('tiered mode: band edges belong to the lower band', () {
    expect(tariff.feeMinorFor(1), 100);
    expect(tariff.feeMinorFor(5000), 100);
    expect(tariff.feeMinorFor(5001), 300);
    expect(tariff.feeMinorFor(20000), 300);
    expect(tariff.feeMinorFor(20001), 700);
    expect(tariff.feeMinorFor(100000), 1100);
    expect(tariff.feeMinorFor(100001), 1500);
    expect(tariff.feeMinorFor(1000000), 15000);
  });

  test('a capped tariff refuses amounts above its last limit', () {
    expect(capped.feeMinorFor(50000), 200);
    expect(capped.feeMinorFor(50001), isNull);
    expect(capped.maxAmountMinor, 50000);
    expect(tariff.maxAmountMinor, isNull);
    expect(const FeeSchedule.percent(0.05).maxAmountMinor, isNull);
  });

  test('valid schedules pass, invalid ones are explained', () {
    expect(tariff.validate(), isNull);
    expect(capped.validate(), isNull);
    expect(const FeeSchedule.percent(0.05).validate(), isNull);
    expect(const FeeSchedule.percent(0.6).validate(), contains('between 0% and 50%'));
    expect(const FeeSchedule.percent(-0.01).validate(), contains('between 0% and 50%'));
    expect(const FeeSchedule.tiered([]).validate(), contains('at least one'));
    expect(
      const FeeSchedule.tiered([FeeTier(upToMinor: 5000), FeeTier(upToMinor: 5000)]).validate(),
      contains('higher than the previous'),
    );
    expect(
      const FeeSchedule.tiered([FeeTier(upToMinor: null), FeeTier(upToMinor: 5000)]).validate(),
      contains('only the last band'),
    );
    expect(const FeeSchedule.tiered([FeeTier(upToMinor: 5000, flatMinor: -1)]).validate(), contains('flat fee'));
    expect(const FeeSchedule.tiered([FeeTier(upToMinor: 5000, percent: 0.9)]).validate(), contains('between 0% and 50%'));
  });

  test('round trip through the settings document', () {
    expect(FeeSchedule.fromMap(tariff.toMap()), tariff);
    expect(FeeSchedule.fromMap(const FeeSchedule.percent(0.07).toMap()), const FeeSchedule.percent(0.07));
    // Older documents only have feePercent.
    expect(FeeSchedule.fromMap({'feePercent': 0.02}), const FeeSchedule.percent(0.02));
    expect(FeeSchedule.fromMap({}), const FeeSchedule.percent(0.05));
    // Garbage tiers parse to an invalid schedule rather than crashing.
    expect(FeeSchedule.fromMap({'feeMode': 'tiered', 'feeTiers': 'nope'}).validate(), contains('at least one'));
    // The percent is always written so older app versions keep working.
    expect(tariff.toMap()['feePercent'], 0.05);
  });
}
