import 'package:flutter/material.dart';

IconData vehicleIcon(String? type) {
  switch (type?.toLowerCase()) {
    case 'boat':
    case 'ship':
      return Icons.directions_boat;
    case 'truck':
      return Icons.local_shipping;
    case 'motorcycle':
    case 'bike':
      return Icons.two_wheeler;
    case 'bus':
      return Icons.directions_bus;
    case 'jet_ski':
      return Icons.surfing;
    default:
      return Icons.directions_car;
  }
}

String vehicleTypeLabel(String? type) {
  switch (type?.toLowerCase()) {
    case 'car':
      return 'Αυτοκίνητο';
    case 'boat':
      return 'Σκάφος';
    case 'jet_ski':
      return 'Jet Ski';
    case 'motorcycle':
      return 'Μοτοσικλέτα';
    case 'truck':
      return 'Φορτηγό';
    case 'van':
      return 'Βαν';
    case 'bus':
      return 'Λεωφορείο';
    default:
      return type ?? '';
  }
}
