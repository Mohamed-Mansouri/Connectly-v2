import '../../../shared/data/local_database.dart';
import '../../auth/data/local_passwords.dart';

/// Fictional, on-phone accounts for the Ariana presentation.
const demoPeoplePassword = 'ConnectlyDemo!2026';

const _demoPeople = <(String, String, String, double, double)>[
  (
    'demo-amal',
    'Demo Amal · Ariana',
    'demo.amal@connectly.invalid',
    36.8680,
    10.1945
  ),
  (
    'demo-sami',
    'Demo Sami · Ariana',
    'demo.sami@connectly.invalid',
    36.8630,
    10.1885
  ),
  (
    'demo-ines',
    'Demo Ines · Ariana',
    'demo.ines@connectly.invalid',
    36.8585,
    10.1920
  ),
  (
    'demo-nour',
    'Demo Nour · ESPRIT',
    'demo.nour@connectly.invalid',
    36.8570,
    10.2060
  ),
  (
    'demo-youssef',
    'Demo Youssef · ESPRIT',
    'demo.youssef@connectly.invalid',
    36.8514,
    10.2015
  ),
  (
    'demo-meriem',
    'Demo Meriem · ESPRIT',
    'demo.meriem@connectly.invalid',
    36.8504,
    10.2085
  ),
];

/// Adds missing demo accounts once; existing profiles, pins, and links are kept.
Future<void> seedDemoPeople(LocalDatabase database,
    {LocalPasswords? passwords}) async {
  final missing = <(String, String, String, double, double)>[];
  for (final person in _demoPeople) {
    final rows = await database.db.query('users',
        columns: ['id'], where: 'id = ?', whereArgs: [person.$1], limit: 1);
    if (rows.isEmpty) missing.add(person);
  }
  if (missing.isEmpty) return;

  final hasher = passwords ?? LocalPasswords();
  final hashes = <String, String>{};
  for (final person in missing) {
    hashes[person.$1] = await hasher.hash(demoPeoplePassword);
  }

  await database.db.transaction((txn) async {
    for (final person in missing) {
      final rows = await txn.query('users',
          columns: ['id'], where: 'id = ?', whereArgs: [person.$1], limit: 1);
      if (rows.isNotEmpty) continue;
      final timestamp = localTimestamp();
      await txn.insert('users', {
        'id': person.$1,
        'name': person.$2,
        'email': person.$3,
        'password_hash': hashes[person.$1],
        'created_at': timestamp,
      });
      await txn.insert('user_locations', {
        'user_id': person.$1,
        'latitude': person.$4,
        'longitude': person.$5,
        'visible': 1,
        'updated_at': timestamp,
      });
    }
  });
}
