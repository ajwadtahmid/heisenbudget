import 'package:flutter/material.dart';

/// An icon a category can use. Categories store only the [key] (text in the
/// database); the picture comes from Flutter's built-in Material icons, so no
/// extra package or download is needed.
///
/// Keys are saved in users' databases: never rename or remove one.
class CategoryIconOption {
  const CategoryIconOption(this.key, this.label, this.icon, this.group);

  final String key;

  /// Spoken by screen readers, shown as a tooltip, and searched.
  final String label;
  final IconData icon;

  /// Which section of the picker it appears in.
  final String group;
}

/// Used for new categories and for any unknown key.
const defaultCategoryIconKey = 'category';

const _general = 'General';
const _food = 'Food & drink';
const _home = 'Home & bills';
const _shopping = 'Shopping & style';
const _health = 'Health & family';
const _transport = 'Getting around';
const _fun = 'Travel & fun';
const _money = 'Money & work';
const _tech = 'Tech & other';

/// The picker's sections, in display order.
const categoryIconGroups = <String>[
  _general,
  _food,
  _home,
  _shopping,
  _health,
  _transport,
  _fun,
  _money,
  _tech,
];

/// The icons offered in the picker, grouped by theme.
const categoryIcons = <CategoryIconOption>[
  // General
  CategoryIconOption('category', 'General', Icons.category_outlined, _general),
  CategoryIconOption('star', 'Star', Icons.star, _general),
  CategoryIconOption('favorite', 'Favorite', Icons.favorite, _general),
  CategoryIconOption('bookmark', 'Bookmark', Icons.bookmark, _general),
  CategoryIconOption('flag', 'Flag', Icons.flag, _general),
  CategoryIconOption('label', 'Label', Icons.label, _general),
  CategoryIconOption('pin', 'Pin', Icons.push_pin, _general),
  CategoryIconOption('idea', 'Idea', Icons.lightbulb, _general),
  CategoryIconOption('trophy', 'Trophy', Icons.emoji_events, _general),
  CategoryIconOption('sparkle', 'Sparkle', Icons.auto_awesome, _general),
  CategoryIconOption('more', 'More', Icons.more_horiz, _general),
  CategoryIconOption('box', 'Box', Icons.inventory_2, _general),
  CategoryIconOption('event', 'Event', Icons.event, _general),
  CategoryIconOption('calendar', 'Calendar', Icons.calendar_month, _general),
  CategoryIconOption('alarm', 'Alarm', Icons.alarm, _general),
  CategoryIconOption('timer', 'Timer', Icons.timer, _general),
  CategoryIconOption('globe', 'World', Icons.public, _general),

  // Food and drink
  CategoryIconOption('restaurant', 'Restaurant', Icons.restaurant, _food),
  CategoryIconOption('fastfood', 'Fast food', Icons.fastfood, _food),
  CategoryIconOption('cafe', 'Coffee', Icons.local_cafe, _food),
  CategoryIconOption(
    'groceries',
    'Groceries',
    Icons.local_grocery_store,
    _food,
  ),
  CategoryIconOption('bar', 'Drinks', Icons.local_bar, _food),
  CategoryIconOption('cake', 'Treats', Icons.cake, _food),
  CategoryIconOption('breakfast', 'Breakfast', Icons.breakfast_dining, _food),
  CategoryIconOption('lunch', 'Lunch', Icons.lunch_dining, _food),
  CategoryIconOption('dinner', 'Dinner', Icons.dinner_dining, _food),
  CategoryIconOption('noodles', 'Noodles', Icons.ramen_dining, _food),
  CategoryIconOption('pizza', 'Pizza', Icons.local_pizza, _food),
  CategoryIconOption('icecream', 'Ice cream', Icons.icecream, _food),
  CategoryIconOption('bakery', 'Bakery', Icons.bakery_dining, _food),
  CategoryIconOption('takeaway', 'Takeaway', Icons.takeout_dining, _food),
  CategoryIconOption('rice', 'Rice', Icons.rice_bowl, _food),
  CategoryIconOption('seafood', 'Seafood', Icons.set_meal, _food),
  CategoryIconOption('tapas', 'Snacks', Icons.tapas, _food),
  CategoryIconOption('egg', 'Eggs', Icons.egg, _food),
  CategoryIconOption('coffeecup', 'Tea and coffee', Icons.coffee, _food),
  CategoryIconOption('wine', 'Wine', Icons.wine_bar, _food),
  CategoryIconOption('beer', 'Beer', Icons.sports_bar, _food),
  CategoryIconOption('liquor', 'Liquor', Icons.liquor, _food),
  CategoryIconOption('drink', 'Soft drink', Icons.local_drink, _food),
  CategoryIconOption('nightlife', 'Night out', Icons.nightlife, _food),
  CategoryIconOption('kitchen', 'Kitchen', Icons.kitchen, _food),
  CategoryIconOption('microwave', 'Microwave', Icons.microwave, _food),

  // Home and bills
  CategoryIconOption('home', 'Home', Icons.home, _home),
  CategoryIconOption('bills', 'Bills', Icons.receipt_long, _home),
  CategoryIconOption('electricity', 'Electricity', Icons.bolt, _home),
  CategoryIconOption('water', 'Water', Icons.water_drop, _home),
  CategoryIconOption('internet', 'Internet', Icons.wifi, _home),
  CategoryIconOption('phone', 'Phone', Icons.phone_android, _home),
  CategoryIconOption('repairs', 'Repairs', Icons.build, _home),
  CategoryIconOption('laundry', 'Laundry', Icons.local_laundry_service, _home),
  CategoryIconOption('apartment', 'Apartment', Icons.apartment, _home),
  CategoryIconOption('bed', 'Bed', Icons.bed, _home),
  CategoryIconOption('chair', 'Chair', Icons.chair, _home),
  CategoryIconOption('sofa', 'Sofa', Icons.weekend, _home),
  CategoryIconOption('livingroom', 'Living room', Icons.living, _home),
  CategoryIconOption('bathtub', 'Bathtub', Icons.bathtub, _home),
  CategoryIconOption('shower', 'Shower', Icons.shower, _home),
  CategoryIconOption('television', 'Television', Icons.tv, _home),
  CategoryIconOption('router', 'Router', Icons.router, _home),
  CategoryIconOption('garden', 'Garden', Icons.yard, _home),
  CategoryIconOption('fence', 'Fence', Icons.fence, _home),
  CategoryIconOption('roof', 'Roof', Icons.roofing, _home),
  CategoryIconOption('plumbing', 'Plumbing', Icons.plumbing, _home),
  CategoryIconOption('cleaning', 'Cleaning', Icons.cleaning_services, _home),
  CategoryIconOption('carpenter', 'Carpentry', Icons.carpenter, _home),
  CategoryIconOption('handyman', 'Handyman', Icons.handyman, _home),
  CategoryIconOption('key', 'Keys', Icons.key, _home),
  CategoryIconOption('lock', 'Lock', Icons.lock, _home),
  CategoryIconOption('heating', 'Heating', Icons.hvac, _home),
  CategoryIconOption('cooling', 'Cooling', Icons.ac_unit, _home),
  CategoryIconOption('thermostat', 'Thermostat', Icons.thermostat, _home),
  CategoryIconOption('garage', 'Garage', Icons.garage, _home),
  CategoryIconOption('lightbulb', 'Lighting', Icons.light, _home),
  CategoryIconOption('countertop', 'Countertop', Icons.countertops, _home),
  CategoryIconOption('window', 'Window', Icons.window, _home),

  // Shopping and style
  CategoryIconOption('shopping', 'Shopping', Icons.shopping_bag, _shopping),
  CategoryIconOption('cart', 'Cart', Icons.shopping_cart, _shopping),
  CategoryIconOption('basket', 'Basket', Icons.shopping_basket, _shopping),
  CategoryIconOption('clothes', 'Clothes', Icons.checkroom, _shopping),
  CategoryIconOption('haircut', 'Haircut', Icons.content_cut, _shopping),
  CategoryIconOption('spa', 'Self care', Icons.spa, _shopping),
  CategoryIconOption('store', 'Store', Icons.store, _shopping),
  CategoryIconOption('storefront', 'Shop front', Icons.storefront, _shopping),
  CategoryIconOption('mall', 'Mall', Icons.local_mall, _shopping),
  CategoryIconOption('giftbox', 'Present', Icons.redeem, _shopping),
  CategoryIconOption('jewelry', 'Jewelry', Icons.diamond, _shopping),
  CategoryIconOption('watch', 'Watch', Icons.watch, _shopping),
  CategoryIconOption('face', 'Face', Icons.face, _shopping),
  CategoryIconOption(
    'makeup',
    'Makeup',
    Icons.face_retouching_natural,
    _shopping,
  ),
  CategoryIconOption('brush', 'Brush', Icons.brush, _shopping),
  CategoryIconOption(
    'drycleaning',
    'Dry cleaning',
    Icons.dry_cleaning,
    _shopping,
  ),
  CategoryIconOption('sale', 'Sale', Icons.local_offer, _shopping),
  CategoryIconOption('sell', 'Price tag', Icons.sell, _shopping),
  CategoryIconOption('backpack', 'Backpack', Icons.backpack, _shopping),
  CategoryIconOption('toys', 'Toys', Icons.toys, _shopping),
  CategoryIconOption('style', 'Style', Icons.style, _shopping),
  CategoryIconOption('iron', 'Ironing', Icons.iron, _shopping),

  // Health and family
  CategoryIconOption('medical', 'Medical', Icons.medical_services, _health),
  CategoryIconOption('fitness', 'Fitness', Icons.fitness_center, _health),
  CategoryIconOption('pets', 'Pets', Icons.pets, _health),
  CategoryIconOption('kids', 'Kids', Icons.child_care, _health),
  CategoryIconOption('school', 'School', Icons.school, _health),
  CategoryIconOption('medication', 'Medication', Icons.medication, _health),
  CategoryIconOption('vaccine', 'Vaccine', Icons.vaccines, _health),
  CategoryIconOption(
    'safety',
    'Health cover',
    Icons.health_and_safety,
    _health,
  ),
  CategoryIconOption('heartbeat', 'Heart health', Icons.monitor_heart, _health),
  CategoryIconOption('therapy', 'Therapy', Icons.psychology, _health),
  CategoryIconOption('healing', 'Healing', Icons.healing, _health),
  CategoryIconOption('hospital', 'Hospital', Icons.local_hospital, _health),
  CategoryIconOption('pharmacy', 'Pharmacy', Icons.local_pharmacy, _health),
  CategoryIconOption('blood', 'Blood test', Icons.bloodtype, _health),
  CategoryIconOption('family', 'Family', Icons.family_restroom, _health),
  CategoryIconOption('elderly', 'Elder care', Icons.elderly, _health),
  CategoryIconOption(
    'meditation',
    'Meditation',
    Icons.self_improvement,
    _health,
  ),
  CategoryIconOption('yoga', 'Yoga', Icons.sports_gymnastics, _health),
  CategoryIconOption('running', 'Running', Icons.directions_run, _health),
  CategoryIconOption('book', 'Books', Icons.book, _health),
  CategoryIconOption('science', 'Science', Icons.science, _health),
  CategoryIconOption('baby', 'Baby', Icons.baby_changing_station, _health),
  CategoryIconOption('wheelchair', 'Accessibility', Icons.accessible, _health),
  CategoryIconOption(
    'dentist',
    'Dentist',
    Icons.sentiment_satisfied_alt,
    _health,
  ),
  CategoryIconOption('glasses', 'Glasses', Icons.visibility, _health),
  CategoryIconOption('hearing', 'Hearing', Icons.hearing, _health),

  // Getting around
  CategoryIconOption('bus', 'Bus', Icons.directions_bus, _transport),
  CategoryIconOption('car', 'Car', Icons.directions_car, _transport),
  CategoryIconOption('fuel', 'Fuel', Icons.local_gas_station, _transport),
  CategoryIconOption('train', 'Train', Icons.train, _transport),
  CategoryIconOption('taxi', 'Taxi', Icons.local_taxi, _transport),
  CategoryIconOption('bike', 'Bicycle', Icons.pedal_bike, _transport),
  CategoryIconOption('motorbike', 'Motorbike', Icons.two_wheeler, _transport),
  CategoryIconOption('scooter', 'Scooter', Icons.moped, _transport),
  CategoryIconOption('subway', 'Subway', Icons.subway, _transport),
  CategoryIconOption('tram', 'Tram', Icons.tram, _transport),
  CategoryIconOption('boat', 'Boat', Icons.directions_boat, _transport),
  CategoryIconOption('walk', 'Walking', Icons.directions_walk, _transport),
  CategoryIconOption(
    'electriccar',
    'Electric car',
    Icons.electric_car,
    _transport,
  ),
  CategoryIconOption('charging', 'Charging', Icons.ev_station, _transport),
  CategoryIconOption('carrepair', 'Car repair', Icons.car_repair, _transport),
  CategoryIconOption('parking', 'Parking', Icons.local_parking, _transport),
  CategoryIconOption('traffic', 'Traffic', Icons.traffic, _transport),
  CategoryIconOption('shuttle', 'Shuttle', Icons.airport_shuttle, _transport),
  CategoryIconOption('commute', 'Commute', Icons.commute, _transport),
  CategoryIconOption('shipping', 'Delivery', Icons.local_shipping, _transport),
  CategoryIconOption(
    'rickshaw',
    'Rickshaw',
    Icons.electric_rickshaw,
    _transport,
  ),
  CategoryIconOption('carwash', 'Car wash', Icons.local_car_wash, _transport),
  CategoryIconOption('toll', 'Toll', Icons.toll, _transport),
  CategoryIconOption('flight', 'Flight', Icons.flight, _transport),
  CategoryIconOption('helicopter', 'Helicopter', Icons.airlines, _transport),

  // Travel and fun
  CategoryIconOption('hotel', 'Hotel', Icons.hotel, _fun),
  CategoryIconOption('beach', 'Holiday', Icons.beach_access, _fun),
  CategoryIconOption('luggage', 'Luggage', Icons.luggage, _fun),
  CategoryIconOption('map', 'Map', Icons.map, _fun),
  CategoryIconOption('explore', 'Explore', Icons.explore, _fun),
  CategoryIconOption('camping', 'Camping', Icons.holiday_village, _fun),
  CategoryIconOption('hiking', 'Hiking', Icons.hiking, _fun),
  CategoryIconOption('mountain', 'Mountains', Icons.landscape, _fun),
  CategoryIconOption('park', 'Park', Icons.park, _fun),
  CategoryIconOption('surfing', 'Surfing', Icons.surfing, _fun),
  CategoryIconOption('kayaking', 'Kayaking', Icons.kayaking, _fun),
  CategoryIconOption('skiing', 'Skiing', Icons.downhill_skiing, _fun),
  CategoryIconOption('golf', 'Golf', Icons.golf_course, _fun),
  CategoryIconOption('football', 'Football', Icons.sports_soccer, _fun),
  CategoryIconOption('basketball', 'Basketball', Icons.sports_basketball, _fun),
  CategoryIconOption('tennis', 'Tennis', Icons.sports_tennis, _fun),
  CategoryIconOption('cricket', 'Cricket', Icons.sports_cricket, _fun),
  CategoryIconOption('baseball', 'Baseball', Icons.sports_baseball, _fun),
  CategoryIconOption(
    'martialarts',
    'Martial arts',
    Icons.sports_martial_arts,
    _fun,
  ),
  CategoryIconOption('pool', 'Swimming', Icons.pool, _fun),
  CategoryIconOption('movie', 'Movies', Icons.movie, _fun),
  CategoryIconOption('games', 'Games', Icons.sports_esports, _fun),
  CategoryIconOption('gamepad', 'Console', Icons.videogame_asset, _fun),
  CategoryIconOption('music', 'Music', Icons.music_note, _fun),
  CategoryIconOption('piano', 'Piano', Icons.piano, _fun),
  CategoryIconOption('headphones', 'Headphones', Icons.headphones, _fun),
  CategoryIconOption('microphone', 'Microphone', Icons.mic, _fun),
  CategoryIconOption('celebration', 'Celebration', Icons.celebration, _fun),
  CategoryIconOption('gift', 'Gift', Icons.card_giftcard, _fun),
  CategoryIconOption('charity', 'Charity', Icons.volunteer_activism, _fun),
  CategoryIconOption('theatre', 'Theatre', Icons.theater_comedy, _fun),
  CategoryIconOption('tickets', 'Tickets', Icons.local_activity, _fun),
  CategoryIconOption('festival', 'Festival', Icons.festival, _fun),
  CategoryIconOption('casino', 'Casino', Icons.casino, _fun),
  CategoryIconOption('photo', 'Photography', Icons.photo_camera, _fun),
  CategoryIconOption('art', 'Art', Icons.palette, _fun),
  CategoryIconOption('mosque', 'Mosque', Icons.mosque, _fun),
  CategoryIconOption('church', 'Church', Icons.church, _fun),
  CategoryIconOption('temple', 'Temple', Icons.temple_hindu, _fun),
  CategoryIconOption(
    'prayer',
    'Prayer',
    Icons.volunteer_activism_outlined,
    _fun,
  ),

  // Money and work
  CategoryIconOption('salary', 'Salary', Icons.payments, _money),
  CategoryIconOption('cash', 'Cash', Icons.attach_money, _money),
  CategoryIconOption('card', 'Card', Icons.credit_card, _money),
  CategoryIconOption('bank', 'Bank', Icons.account_balance, _money),
  CategoryIconOption('savings', 'Savings', Icons.savings, _money),
  CategoryIconOption('work', 'Work', Icons.work, _money),
  CategoryIconOption('freelance', 'Freelance', Icons.laptop, _money),
  CategoryIconOption('quote', 'Invoice', Icons.request_quote, _money),
  CategoryIconOption('receipt', 'Receipt', Icons.receipt, _money),
  CategoryIconOption('paid', 'Paid', Icons.paid, _money),
  CategoryIconOption('pricecheck', 'Price check', Icons.price_check, _money),
  CategoryIconOption('wallet', 'Wallet', Icons.account_balance_wallet, _money),
  CategoryIconOption('exchange', 'Exchange', Icons.currency_exchange, _money),
  CategoryIconOption('growth', 'Growth', Icons.trending_up, _money),
  CategoryIconOption('decline', 'Decline', Icons.trending_down, _money),
  CategoryIconOption('chart', 'Chart', Icons.show_chart, _money),
  CategoryIconOption('piechart', 'Pie chart', Icons.pie_chart, _money),
  CategoryIconOption('calculator', 'Calculator', Icons.calculate, _money),
  CategoryIconOption('percent', 'Percent', Icons.percent, _money),
  CategoryIconOption('handshake', 'Deal', Icons.handshake, _money),
  CategoryIconOption('business', 'Business', Icons.business_center, _money),
  CategoryIconOption('atm', 'ATM', Icons.local_atm, _money),
  CategoryIconOption('coin', 'Coin', Icons.monetization_on, _money),
  CategoryIconOption('euro', 'Euro', Icons.euro, _money),
  CategoryIconOption('pound', 'Pound', Icons.currency_pound, _money),
  CategoryIconOption('rupee', 'Rupee', Icons.currency_rupee, _money),
  CategoryIconOption('yen', 'Yen', Icons.currency_yen, _money),
  CategoryIconOption('bitcoin', 'Bitcoin', Icons.currency_bitcoin, _money),
  CategoryIconOption('legal', 'Legal', Icons.gavel, _money),
  CategoryIconOption('balance', 'Balance', Icons.balance, _money),
  CategoryIconOption('tax', 'Tax', Icons.account_balance_outlined, _money),
  CategoryIconOption('insurance', 'Insurance', Icons.shield, _money),
  CategoryIconOption('badge', 'ID badge', Icons.badge, _money),
  CategoryIconOption('support', 'Support', Icons.support_agent, _money),
  CategoryIconOption('engineering', 'Engineering', Icons.engineering, _money),
  CategoryIconOption('moneyoff', 'Refund', Icons.money_off, _money),
  CategoryIconOption('trade', 'Trade', Icons.swap_horiz, _money),

  // Tech and other
  CategoryIconOption('computer', 'Computer', Icons.computer, _tech),
  CategoryIconOption('code', 'Code', Icons.code, _tech),
  CategoryIconOption('tablet', 'Tablet', Icons.tablet_mac, _tech),
  CategoryIconOption('headset', 'Headset', Icons.headset_mic, _tech),
  CategoryIconOption('print', 'Printer', Icons.print, _tech),
  CategoryIconOption('cloud', 'Cloud', Icons.cloud, _tech),
  CategoryIconOption('storage', 'Storage', Icons.storage, _tech),
  CategoryIconOption('devices', 'Devices', Icons.devices, _tech),
  CategoryIconOption(
    'subscriptions',
    'Subscriptions',
    Icons.subscriptions,
    _tech,
  ),
  CategoryIconOption('stream', 'Streaming', Icons.play_circle, _tech),
  CategoryIconOption('podcast', 'Podcast', Icons.podcasts, _tech),
  CategoryIconOption('news', 'News', Icons.newspaper, _tech),
  CategoryIconOption('article', 'Article', Icons.article, _tech),
  CategoryIconOption('mail', 'Mail', Icons.mail, _tech),
  CategoryIconOption('post', 'Post office', Icons.local_post_office, _tech),
  CategoryIconOption('translate', 'Translate', Icons.translate, _tech),
  CategoryIconOption('rocket', 'Rocket', Icons.rocket_launch, _tech),
  CategoryIconOption('security', 'Security', Icons.security, _tech),
  CategoryIconOption(
    'notifications',
    'Notifications',
    Icons.notifications,
    _tech,
  ),
  CategoryIconOption('settings', 'Settings', Icons.settings, _tech),
  CategoryIconOption('recycle', 'Recycling', Icons.recycling, _tech),
  CategoryIconOption('eco', 'Eco', Icons.eco, _tech),
  CategoryIconOption('sun', 'Solar', Icons.wb_sunny, _tech),
  CategoryIconOption('weather', 'Weather', Icons.cloud_queue, _tech),
  CategoryIconOption('fire', 'Fire', Icons.local_fire_department, _tech),
  CategoryIconOption('construction', 'Construction', Icons.construction, _tech),
];

/// The option for [key], or the general one when the key is missing or no
/// longer known.
CategoryIconOption categoryIconFor(String? key) {
  for (final option in categoryIcons) {
    if (option.key == key) return option;
  }
  return categoryIcons.first;
}

/// Icons matching [query]. Every word must appear in the icon's name, key or
/// section, ignoring case, so "food", "car wash" and "elec" all find things.
/// An empty query returns everything.
List<CategoryIconOption> searchCategoryIcons(String query) {
  final words = query
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return categoryIcons;
  return [
    for (final option in categoryIcons)
      if (words.every(
        (w) => '${option.label} ${option.key} ${option.group}'
            .toLowerCase()
            .contains(w),
      ))
        option,
  ];
}
