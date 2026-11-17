import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How often a subscription renews.
enum ZtBillingPeriod { month, year }

/// Something the store in this build can sell: one row of
/// `zt_billing_products` with the store's own, localised price.
class ZtStoreOffer {
  const ZtStoreOffer({
    required this.productId,
    required this.planId,
    required this.period,
    required this.price,
  });

  /// `zt_billing_products.id`, e.g. `plus_monthly_play`.
  final String productId;

  /// The plan it gives, e.g. `plus`.
  final String planId;
  final ZtBillingPeriod period;

  /// The price as the store formats it for this person ("$2.99", "₪10.90").
  /// Never computed by the app: the store decides currency and tax.
  final String price;
}

/// What happened when someone tried to buy.
enum ZtPurchaseOutcome {
  /// Paid and verified by the server; the plan is on the account.
  purchased,

  /// The store accepted it but the payment isn't through yet (some payment
  /// methods take a while). The plan appears once the server hears.
  pending,

  /// The person closed the store's sheet.
  canceled,

  /// Something went wrong; nothing was charged.
  failed,
}

/// The store this build sells through: Google Play Billing in Play builds,
/// Apple in App Store builds, the web checkout in direct builds.
///
/// A store only starts the purchase and hands the receipt to the server.
/// The server verifies it with the store and puts the plan on the account
/// (`zt_apply_billing_event`); the app never decides on its own that
/// someone has paid.
abstract interface class ZtBillingStore {
  /// What can be bought here, with prices. Empty when nothing is for sale.
  Future<List<ZtStoreOffer>> offers();

  /// Starts the store's purchase flow for [offer].
  Future<ZtPurchaseOutcome> buy(ZtStoreOffer offer);

  /// Sends existing purchases to the server again (new phone, reinstall).
  Future<void> restore();

  /// Opens the store's page where people cancel or change a subscription.
  Future<void> manage();
}

/// The store for this build. Null until one is connected: the plans
/// screen then says Plus can't be bought yet. Apps override it once their
/// store is set up.
final ztBillingStoreProvider = Provider<ZtBillingStore?>((ref) => null);

/// A store that never charges anyone, for tests, previews and trying the
/// plans screen before a real store is connected.
class FakeBillingStore implements ZtBillingStore {
  FakeBillingStore({
    List<ZtStoreOffer>? offers,
    this.outcome = ZtPurchaseOutcome.purchased,
    this.onPurchased,
  }) : _offers = offers ??
            const [
              ZtStoreOffer(
                  productId: 'plus_monthly_fake',
                  planId: 'plus',
                  period: ZtBillingPeriod.month,
                  price: r'$2.99'),
              ZtStoreOffer(
                  productId: 'plus_yearly_fake',
                  planId: 'plus',
                  period: ZtBillingPeriod.year,
                  price: r'$29.00'),
            ];

  final List<ZtStoreOffer> _offers;

  /// What [buy] returns.
  ZtPurchaseOutcome outcome;

  /// Called after a successful [buy], e.g. to switch a fake plan source.
  final void Function(ZtStoreOffer offer)? onPurchased;

  final bought = <ZtStoreOffer>[];
  var restored = 0;
  var managed = 0;

  @override
  Future<List<ZtStoreOffer>> offers() async => _offers;

  @override
  Future<ZtPurchaseOutcome> buy(ZtStoreOffer offer) async {
    if (outcome == ZtPurchaseOutcome.purchased) {
      bought.add(offer);
      onPurchased?.call(offer);
    }
    return outcome;
  }

  @override
  Future<void> restore() async => restored++;

  @override
  Future<void> manage() async => managed++;
}
