String missionCategoryLabel(String cat) => switch (cat) {
  'trainer' => 'Εκπαιδευτικές',
  'training' => 'Εκπαίδευση',
  'tep' => 'ΤΕΠ',
  'volunteer' => 'Εθελοντικές',
  'sanitary_general' => 'Υγειονομικές Γενικές',
  'sanitary_lifeguard' => 'Υγειονομικές Ναυαγοσωστικές',
  _ => cat,
};
