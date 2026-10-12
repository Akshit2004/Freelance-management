import 'package:flutter_test/flutter_test.dart';
import 'package:freelance_os/numwords.dart';

void main() {
  test('spoken numbers become digits', () {
    final cases = {
      'three reels at two thousand rupees each': '3 reels at 2000 rupees each',
      'eight hours of editing at eighty five': '8 hours of editing at 85',
      'eighteen percent gst': '18 percent gst',
      'due in seven days': 'due in 7 days',
      'logo design for eight thousand': 'logo design for 8000',
      'two thousand five hundred': '2500',
      'one hundred and five': '105',
      'one thousand two hundred and fifty': '1250',
      'one lakh twenty thousand': '120000',
      'two crore': '20000000',
      'a hundred': 'a 100',
      'hundred': '100',
      'twenty one': '21',
      'twelve hundred': '1200',
      'one point five lakh': '150000',
      'two point five': '2.5',
      'zero': '0',
    };
    cases.forEach((input, want) => expect(wordsToDigits(input), want, reason: input));
  });

  test('separate numbers stay separate', () {
    expect(wordsToDigits('three four'), '3 4');
    expect(wordsToDigits('five twenty'), '5 20');
    expect(wordsToDigits('two reels five banners'), '2 reels 5 banners');
    expect(wordsToDigits('twenty thirteen'), '20 13');
  });

  test('digits and other text are left alone; grouped digits from recognizers are joined', () {
    expect(wordsToDigits('Logo designed 8 000'), 'Logo designed 8000');
    expect(wordsToDigits('12 000 rupees'), '12000 rupees');
    expect(wordsToDigits('1 000 000'), '1000000');
    expect(wordsToDigits('3 reels @ 2000, tax 18%'), '3 reels @ 2000, tax 18%');
    expect(wordsToDigits('someone'), 'someone', reason: '"one" inside a word is not a number');
    expect(wordsToDigits('Anyone ten'), 'Anyone 10');
    expect(wordsToDigits(''), '');
  });
}
