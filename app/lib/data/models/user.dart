import 'package:fade_call/data/models/json.dart';

enum Role {
  client('Client'),
  barber('Barber'),
  operator('Operator');

  const Role(this.label);
  final String label;

  static Role parse(String value) => Role.values.byName(value);
}

final class AppUser {
  const AppUser({
    required this.id,
    required this.role,
    required this.name,
    required this.phone,
  });

  factory AppUser.fromJson(Json json) => AppUser(
    id: json.str('id'),
    role: Role.parse(json.str('role')),
    name: json.str('name'),
    phone: json.str('phone'),
  );

  final String id;
  final Role role;
  final String name;
  final String phone;

  Json toJson() => {'id': id, 'role': role.name, 'name': name, 'phone': phone};
}

final class Session {
  const Session({required this.token, required this.user});

  factory Session.fromJson(Json json) => Session(
    token: json.str('token'),
    user: AppUser.fromJson(json.obj('user')),
  );

  final String token;
  final AppUser user;

  Json toJson() => {'token': token, 'user': user.toJson()};
}

final class Health {
  const Health({
    required this.status,
    required this.mode,
    required this.models,
  });

  factory Health.fromJson(Json json) => Health(
    status: json.str('status'),
    mode: json.str('mode'),
    models: json.stringMap('models'),
  );

  final String status;
  final String mode;
  final Map<String, String> models;

  bool get isMock => mode == 'mock';
}

final class Area {
  const Area({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
  });

  factory Area.fromJson(Json json) => Area(
    id: json.str('id'),
    name: json.str('name'),
    lat: json.dbl('lat'),
    lng: json.dbl('lng'),
  );

  final String id;
  final String name;
  final double lat;
  final double lng;
}
