import 'package:flutter_test/flutter_test.dart';
import 'package:freelance_os/models.dart';

void main() {
  test('activity feed logs real changes and nothing at baseline', () {
    final s = Store()
      ..clients = [Client(id: 'c', name: 'Acme')]
      ..projects = [Project(id: 'p', clientId: 'c', name: 'Site', todos: [Todo(id: 't', text: 'Logo')])]
      ..docs = [Doc(id: 'd', kind: 'invoice', number: 'INV-1', clientId: 'c')];
    s.baseline();
    s.save();
    expect(s.activity, isEmpty);

    s.docs.first.status = 'paid';
    s.projects.first.todos.first.done = true;
    s.save();
    expect(s.activity.map((a) => a.text), containsAll(['Done · Logo (Site)', 'INV-1 paid by Acme · ₹0']));

    s.deleteDoc('d');
    expect(s.activity.first.text, 'Deleted · INV-1');
    s.putClient(Client(name: 'Zed'));
    expect(s.activity.first.text, 'New client · Zed');
  });
}
