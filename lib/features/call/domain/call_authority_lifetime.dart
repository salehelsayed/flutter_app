/// Default lease for newly issued call endpoints, per-contact wake grants,
/// and typed push registrations. It matches the existing push-token lease so
/// a suspended app does not lose call reachability after only a few hours.
///
/// Each record retains its own expiry and signature, device epoch, contact,
/// and revocation checks. Existing grants keep their original signed expiry;
/// changing this default does not renew them or their distribution receipts.
const Duration callBackgroundReachabilityLifetime = Duration(days: 30);
