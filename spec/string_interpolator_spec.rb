require 'string_interpolator'

RSpec.describe StringInterpolator do
  describe '#interpolate' do
    let(:subject) { described_class.new.add(a: 'one', b: 'two') }

    it 'interpolates' do
      expect(subject.interpolate('%a - %b')).to eq('one - two')
    end

    it 'complains when the string contains a dangling percent sign' do
      expect { subject.interpolate('%') }.to raise_error(StringInterpolator::Error)
    end

    it 'complains when a nonexistent placeholder is used' do
      expect { subject.interpolate('%x') }.to raise_error(StringInterpolator::Error)
    end

    it 'includes a literal percent sign when encountering %%' do
      expect(subject.interpolate('%%')).to eq('%')
    end

    it 'works in pathological cases' do
      expect(subject.interpolate('%a')).to eq('one')
      expect(subject.interpolate('%%a')).to eq('%a')
      expect(subject.interpolate('%%%a')).to eq('%one')
      expect(subject.interpolate('%%%%a')).to eq('%%a')
    end

    context 'required placeholders' do
      let(:subject) { described_class.new.add(a: 'one', b: 'two').require(:a) }

      it "complains when they aren't used" do
        expect { subject.interpolate('%b') }.to raise_error(StringInterpolator::Error)
      end

      it 'works when they are used' do
        expect(subject.interpolate('%a')).to eq('one')
      end
    end

    context 'with herald literals disabled' do
      let(:subject) { described_class.new(literal: false).add(a: 'one') }

      it "doesn't allow herald literals" do
        expect { subject.interpolate('%%') }.to raise_error(StringInterpolator::Error)
      end
    end

    context 'with a multi-character herald' do
      let(:subject) { described_class.new('!!!').add(a: 'one') }

      it 'works' do
        expect(subject.interpolate('!!!a')).to eq('one')
        expect(subject.interpolate('!!a')).to eq('!!a')
      end
    end
  end

  it "doesn't allow conflicting literals" do
    expect { described_class.new.add(foo: 'one', foobar: 'two') }.to raise_error(StringInterpolator::Error)
  end

  it 'allows setting an empty placeholder with herald literals disabled' do
    expect(described_class.new(literal: false).add('' => 'two').interpolate('one%three')).to eq('onetwothree')
  end
end