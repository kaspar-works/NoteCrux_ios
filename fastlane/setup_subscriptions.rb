#!/usr/bin/env ruby
# frozen_string_literal: true

require "fastlane"
require "spaceship"

BUNDLE_ID        = "com.codergautamyt.NoteCrux"
KEY_ID           = "6H4P2FCSJB"
ISSUER_ID        = "8e2974d6-68fc-4cc6-8d3b-26cdd0fdf69d"
KEY_P8           = File.expand_path("~/.appstoreconnect/AuthKey_6H4P2FCSJB.p8")

GROUP_REF_NAME   = "NoteCrux Pro"
GROUP_DISPLAY    = "NoteCrux Pro"

PRODUCTS = [
  {
    product_id:   "com.notecrux.pro.monthly",
    reference:    "NoteCrux Pro Monthly",
    period:       "ONE_MONTH",
    display_name: "NoteCrux Pro Monthly",
    description:  "Unlock unlimited meetings, AI summaries, smart insights, unlimited tasks, and full export. Billed monthly, cancel anytime.",
    price_usd:    "4.99"
  },
  {
    product_id:   "com.notecrux.pro.yearly",
    reference:    "NoteCrux Pro Yearly",
    period:       "ONE_YEAR",
    display_name: "NoteCrux Pro Yearly",
    description:  "Unlock unlimited meetings, AI summaries, smart insights, unlimited tasks, and full export. Billed yearly — save 33% vs monthly.",
    price_usd:    "39.99"
  }
]

def log(msg)
  puts "▸ #{msg}"
end

# ---- Authenticate -------------------------------------------------------

log "Authenticating with App Store Connect API…"
token = Spaceship::ConnectAPI::Token.create(
  key_id:    KEY_ID,
  issuer_id: ISSUER_ID,
  filepath:  KEY_P8
)
Spaceship::ConnectAPI.token = token

# ---- Resolve app --------------------------------------------------------

log "Looking up app #{BUNDLE_ID}…"
app = Spaceship::ConnectAPI::App.find(BUNDLE_ID)
raise "App not found for bundle id #{BUNDLE_ID}" unless app
log "  App ID: #{app.id} (#{app.name})"

# ---- Find or create subscription group ----------------------------------

log "Fetching subscription groups…"
groups = Spaceship::ConnectAPI.get_subscription_groups(
  app_id: app.id,
  filter: { referenceName: GROUP_REF_NAME }
).to_models

group = groups.first
if group
  log "  Found existing group: #{group.id} (#{group.reference_name})"
else
  log "Creating subscription group '#{GROUP_REF_NAME}'…"
  resp = Spaceship::ConnectAPI.post_subscription_group(
    app_id:         app.id,
    reference_name: GROUP_REF_NAME
  )
  group = resp.to_models.first
  log "  Created group: #{group.id}"
end

# ---- Group localization --------------------------------------------------

log "Ensuring group localization (en-US)…"
locs = Spaceship::ConnectAPI.get_subscription_group_localizations(
  subscription_group_id: group.id
).to_models
existing = locs.find { |l| l.locale == "en-US" }
if existing
  log "  en-US localization already present (#{existing.id})"
else
  Spaceship::ConnectAPI.post_subscription_group_localization(
    subscription_group_id: group.id,
    locale: "en-US",
    name:   GROUP_DISPLAY,
    custom_app_name: nil
  )
  log "  Added en-US localization"
end

# ---- Create subscriptions ------------------------------------------------

PRODUCTS.each do |p|
  log "--- #{p[:reference]} (#{p[:product_id]}) ---"

  existing_subs = Spaceship::ConnectAPI.get_subscriptions(
    subscription_group_id: group.id,
    filter: { productId: p[:product_id] }
  ).to_models

  sub = existing_subs.first
  if sub
    log "  Subscription already exists (#{sub.id}); skipping creation"
  else
    log "  Creating subscription…"
    resp = Spaceship::ConnectAPI.post_subscription(
      subscription_group_id: group.id,
      name:                   p[:reference],
      product_id:             p[:product_id],
      subscription_period:    p[:period],
      family_sharable:        false,
      available_in_all_territories: true
    )
    sub = resp.to_models.first
    log "  Created subscription: #{sub.id}"
  end

  # Localization
  sub_locs = Spaceship::ConnectAPI.get_subscription_localizations(
    subscription_id: sub.id
  ).to_models
  if sub_locs.any? { |l| l.locale == "en-US" }
    log "  en-US localization exists"
  else
    log "  Adding en-US localization…"
    Spaceship::ConnectAPI.post_subscription_localization(
      subscription_id: sub.id,
      locale:          "en-US",
      name:            p[:display_name],
      description:     p[:description]
    )
  end

  # Pricing
  prices = Spaceship::ConnectAPI.get_subscription_prices(
    subscription_id: sub.id
  ).to_models
  if prices.any?
    log "  Pricing already configured (#{prices.size} territories)"
  else
    log "  Setting USD $#{p[:price_usd]} base price…"
    point = Spaceship::ConnectAPI.get_subscription_price_points(
      subscription_id: sub.id,
      filter: { "territory" => "USA" }
    ).to_models.find { |pp| pp.customer_price == p[:price_usd] }

    if point.nil?
      warn "  Couldn't find USD $#{p[:price_usd]} price point — skipping price set"
    else
      Spaceship::ConnectAPI.post_subscription_price(
        subscription_id:           sub.id,
        subscription_price_point_id: point.id,
        territory_id:              "USA",
        preserve_current_price:    false
      )
      log "  Price set"
    end
  end
end

log "Done."
