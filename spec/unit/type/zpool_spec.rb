require 'spec_helper'

describe 'zpool' do
  describe Puppet::Type.type(:zpool) do
    properties = [:ensure, :disk, :mirror, :raidz, :spare, :log, :autoexpand, :failmode, :ashift]
    properties.each do |property|
      it "should have a #{property} property" do
        expect(described_class.attrclass(property).ancestors).to be_include(Puppet::Property)
      end
    end

    parameters = [:pool, :raid_parity]
    parameters.each do |parameter|
      it "should have a #{parameter} parameter" do
        expect(described_class.attrclass(parameter).ancestors).to be_include(Puppet::Parameter)
      end
    end
  end

  describe Puppet::Property::VDev do
    let(:resource) { instance_double('resource', :[]= => nil, :property => nil) }
    let(:vdev) do
      described_class.new(
        resource: resource,
      )
    end

    before(:each) do
      described_class.initvars
    end

    it 'is insync if the devices are the same' do
      vdev.should = ['dev1 dev2']
      expect(vdev).to be_safe_insync(['dev2 dev1'])
    end

    it 'is out of sync if the devices are not the same' do
      vdev.should = ['dev1 dev3']
      expect(vdev).not_to be_safe_insync(['dev2 dev1'])
    end

    it 'is insync if the devices are the same and the should values are comma separated' do
      vdev.should = ['dev1', 'dev2']
      expect(vdev).to be_safe_insync(['dev2 dev1'])
    end

    it 'is out of sync if the device is absent and should has a value' do
      vdev.should = ['dev1', 'dev2']
      expect(vdev).not_to be_safe_insync(:absent)
    end

    it 'is insync if the device is absent and should is absent' do
      vdev.should = [:absent]
      expect(vdev).to be_safe_insync(:absent)
    end
  end

  describe Puppet::Property::MultiVDev do
    let(:resource) { instance_double('resource', :[]= => nil, :property => nil) }
    let(:multi_vdev) do
      described_class.new(
        resource: resource,
      )
    end

    before(:each) do
      described_class.initvars
    end

    it 'is insync if the devices are the same' do
      multi_vdev.should = ['dev1 dev2']
      expect(multi_vdev).to be_safe_insync(['dev2 dev1'])
    end

    it 'is out of sync if the devices are not the same' do
      multi_vdev.should = ['dev1 dev3']
      expect(multi_vdev).not_to be_safe_insync(['dev2 dev1'])
    end

    it 'is out of sync if the device is absent and should has a value' do
      multi_vdev.should = ['dev1', 'dev2']
      expect(multi_vdev).not_to be_safe_insync(:absent)
    end

    it 'is insync if the device is absent and should is absent' do
      multi_vdev.should = [:absent]
      expect(multi_vdev).to be_safe_insync(:absent)
    end

    describe 'when there are multiple lists of devices' do
      it 'is in sync if each group has the same devices' do
        multi_vdev.should = ['dev1 dev2', 'dev3 dev4']
        expect(multi_vdev).to be_safe_insync(['dev2 dev1', 'dev3 dev4'])
      end

      it 'is out of sync if any group has the different devices' do
        multi_vdev.should = ['dev1 devX', 'dev3 dev4']
        expect(multi_vdev).not_to be_safe_insync(['dev2 dev1', 'dev3 dev4'])
      end

      it 'is out of sync if devices are in the wrong group' do
        multi_vdev.should = ['dev1 dev2', 'dev3 dev4']
        expect(multi_vdev).not_to be_safe_insync(['dev2 dev3', 'dev1 dev4'])
      end
    end
  end
end
