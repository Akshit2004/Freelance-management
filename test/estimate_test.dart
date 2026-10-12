import 'package:flutter_test/flutter_test.dart';
import 'package:freelance_os/ai.dart';

void main() {
  groupedTests();
  test('ProjectEstimate.parse reads modules with subtasks', () {
    final e = ProjectEstimate.parse('<think>\n\n</think>\n\nProject: CRM. Staff and stock.\nbudget 18,000\nStaff management\n- Staff profiles | 16\n- Attendance: 20h\nInventory:\n- Stock items | 12\nEmpty module\nLaunch | 6')!;
    expect(e.budget, 18000);
    expect(e.todos.map((t) => t.text), ['Staff management', 'Inventory', 'Launch']);
    expect(e.todos.first.sub.map((t) => t.text), ['Staff profiles', 'Attendance']);
    expect(e.hours, 54);
    expect(e.fromRate, false);
  });

  test('ProjectEstimate.parse prices by hourly rate when one is set', () {
    final e = ProjectEstimate.parse('Website\n- Pages | 10\n- Contact form | 2.5', rate: 800)!;
    expect(e.budget, 10000);
    expect(e.fromRate, true);
    expect(ProjectEstimate.parse('Website\n- Pages | 10'), isNull, reason: 'no budget and no rate');
  });
}

void groupedTests() {
  test('ProjectEstimate.parse groups "Module > task | hours" lines into subtasks', () {
    final e = ProjectEstimate.parse(
        'budget 90000\nStaff > Staff profiles | 16\nStaff > Attendance | 20\nInventory > Stock list | 12\nstaff > Roles and access | 8\nBilling > Invoices | 10')!;
    expect(e.todos.map((t) => t.text), ['Staff', 'Inventory', 'Billing']);
    expect(e.todos.first.sub.map((t) => t.text), ['Staff profiles', 'Attendance', 'Roles and access']);
    expect(e.hours, 66);
  });
}
