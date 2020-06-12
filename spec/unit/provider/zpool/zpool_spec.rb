require 'spec_helper'

describe Puppet::Type.type(:zpool).provider(:zpool) do
  let(:name) { 'mypool' }
  let(:zpool) { '/usr/sbin/zpool' }

  let(:resource) do
    Puppet::Type.type(:zpool).new(name: name, provider: :zpool)
  end

  let(:provider) { resource.provider }

  before(:each) do
    allow(provider.class).to receive(:which).with('zpool') { zpool }
    allow(Facter).to receive(:value).with(:kernel).and_return('Linux')
  end

  context '#current_pool' do
    it 'calls process_zpool_data with the result of get_pool_data only once' do
      allow(provider).to receive(:get_pool_data).and_return(['foo', 'disk'])
      allow(provider).to receive(:process_zpool_data).with(['foo', 'disk']) { 'stuff' }
      expect(provider).to receive(:process_zpool_data).with(['foo', 'disk']).once

      provider.current_pool
      provider.current_pool
    end
  end

  describe 'self.instances' do
    it 'has an instances method' do
      expect(provider.class).to respond_to(:instances)
    end

    it 'lists instances' do
      allow(provider.class).to receive(:zpool).with(:list, '-H') { File.read(my_fixture('zpool-list.out')) }
      instances = provider.class.instances.map { |p| { name: p.get(:name), ensure: p.get(:ensure) } }
      expect(instances.size).to eq(2)
      expect(instances[0]).to eq(name: 'rpool', ensure: :present)
      expect(instances[1]).to eq(name: 'mypool', ensure: :present)
    end
  end

  context '#flush' do
    it 'reloads the pool' do
      allow(provider).to receive(:get_pool_data)
      allow(provider).to receive(:process_zpool_data).and_return('stuff')
      expect(provider).to receive(:process_zpool_data).twice
      provider.current_pool
      provider.flush
      provider.current_pool
    end
  end

  context '#process_zpool_data' do
    let(:zpool_data) { ['foo', 'disk'] }

    describe 'when there is no data' do
      it 'returns a hash with ensure=>:absent' do
        expect(provider.process_zpool_data([])[:ensure]).to eq(:absent)
      end
    end

    describe 'when there are full path disks on Linux' do
      it 'munges partitions into disk names' do
        allow(provider).to receive(:execute).with('lsblk -p -no pkname /dev/sdc1').and_return('/dev/sdc')
        allow(provider).to receive(:execute).with('lsblk -p -no pkname /dev/disk/by-id/disk_serial-0:0-part1').and_return('/dev/disk/by-id/disk_serial-0:0')
        zpool_data = ['foo', '/dev/sdc1', '/dev/disk/by-id/disk_serial-0:0-part1']
        expect(provider.process_zpool_data(zpool_data)[:disk]).to eq(['/dev/sdc /dev/disk/by-id/disk_serial-0:0'])
      end
    end

    describe 'when there is a spare' do
      it 'adds the spare disk to the hash' do
        zpool_data.concat ['spares', 'spare_disk']
        expect(provider.process_zpool_data(zpool_data)[:spare]).to eq(['spare_disk'])
      end
    end

    describe 'when there are two spares' do
      it 'adds the spare disk to the hash as a single string' do
        zpool_data.concat ['spares', 'spare_disk', 'spare_disk2']
        expect(provider.process_zpool_data(zpool_data)[:spare]).to eq(['spare_disk spare_disk2'])
      end
    end

    describe 'when there is a log' do
      it 'adds the log disk to the hash' do
        zpool_data.concat ['logs', 'log_disk']
        expect(provider.process_zpool_data(zpool_data)[:log]).to eq(['log_disk'])
      end
    end

    describe 'when there are two logs' do
      it 'adds the log disks to the hash as a single string' do
        zpool_data.concat ['spares', 'spare_disk', 'spare_disk2']
        expect(provider.process_zpool_data(zpool_data)[:spare]).to eq(['spare_disk spare_disk2'])
      end
    end

    describe 'when the vdev is a single mirror' do
      it 'calls create_multi_array with mirror' do
        zpool_data = ['mirrorpool', 'mirror', 'disk1', 'disk2']
        expect(provider.process_zpool_data(zpool_data)[:mirror]).to eq(['disk1 disk2'])
      end
    end

    describe 'when the vdev is a single mirror on solaris 10u9 or later' do
      it 'calls create_multi_array with mirror' do
        zpool_data = ['mirrorpool', 'mirror-0', 'disk1', 'disk2']
        expect(provider.process_zpool_data(zpool_data)[:mirror]).to eq(['disk1 disk2'])
      end
    end

    describe 'when the vdev is a double mirror' do
      it 'calls create_multi_array with mirror' do
        zpool_data = ['mirrorpool', 'mirror', 'disk1', 'disk2', 'mirror', 'disk3', 'disk4']
        expect(provider.process_zpool_data(zpool_data)[:mirror]).to eq(['disk1 disk2', 'disk3 disk4'])
      end
    end

    describe 'when the vdev is a double mirror on solaris 10u9 or later' do
      it 'calls create_multi_array with mirror' do
        zpool_data = ['mirrorpool', 'mirror-0', 'disk1', 'disk2', 'mirror-1', 'disk3', 'disk4']
        expect(provider.process_zpool_data(zpool_data)[:mirror]).to eq(['disk1 disk2', 'disk3 disk4'])
      end
    end

    describe 'when the vdev is a raidz1' do
      it 'calls create_multi_array with raidz1' do
        zpool_data = ['mirrorpool', 'raidz1', 'disk1', 'disk2']
        expect(provider.process_zpool_data(zpool_data)[:raidz]).to eq(['disk1 disk2'])
      end
    end

    describe 'when the vdev is a raidz1 on solaris 10u9 or later' do
      it 'calls create_multi_array with raidz1' do
        zpool_data = ['mirrorpool', 'raidz1-0', 'disk1', 'disk2']
        expect(provider.process_zpool_data(zpool_data)[:raidz]).to eq(['disk1 disk2'])
      end
    end

    describe 'when the vdev is a raidz2' do
      it 'calls create_multi_array with raidz2 and set the raid_parity' do
        zpool_data = ['mirrorpool', 'raidz2', 'disk1', 'disk2']
        pool = provider.process_zpool_data(zpool_data)
        expect(pool[:raidz]).to eq(['disk1 disk2'])
        expect(pool[:raid_parity]).to eq('raidz2')
      end
    end

    describe 'when the vdev is a raidz2 on solaris 10u9 or later' do
      it 'calls create_multi_array with raidz2 and set the raid_parity' do
        zpool_data = ['mirrorpool', 'raidz2-0', 'disk1', 'disk2']
        pool = provider.process_zpool_data(zpool_data)
        expect(pool[:raidz]).to eq(['disk1 disk2'])
        expect(pool[:raid_parity]).to eq('raidz2')
      end
    end
  end

  describe 'when calling the getters and setters for configurable options' do
    [:ashift,:autoexpand,:failmode].each do |field|
      it "should get the #{field} value from the pool" do
        allow(provider).to receive(:zpool).with(:get,'-H', '-o', 'value', field, name).and_return('value')
        expect(provider.send(field)).to eq('value')
      end
      it "should set #{field}=value" do
        expect(provider).to receive(:zpool).with(:set, "#{field}=value", name)
        provider.send("#{field}=", 'value')
      end
    end
  end

  describe 'when calling the getters and setters' do
    [:disk, :mirror, :raidz, :log, :spare].each do |field|
      describe "when calling #{field}" do
        it "should get the #{field} value from the current_pool hash" do
          pool_hash = {}
          pool_hash[field] = 'value'
          allow(provider).to receive(:current_pool) { pool_hash }

          expect(provider.send(field)).to eq('value')
        end
      end

      describe "when setting the #{field}" do
        it "should fail if readonly #{field} values change" do
          allow(provider).to receive(:current_pool) { Hash.new('currentvalue') }
          expect {
            provider.send((field.to_s + '=').to_sym, 'shouldvalue')
          }.to raise_error(Puppet::Error, %r{can\'t be changed})
        end
      end
    end
  end

  context '#create' do
    context 'when creating disks for a zpool' do
      before(:each) do
        resource[:disk] = 'disk1'
      end

      it 'calls create with the build_vdevs value' do
        expect(provider).to receive(:zpool).with(:create, name, 'disk1')
        provider.create
      end

      it "calls create with the 'spares' and 'log' values" do
        resource[:spare] = ['value1']
        resource[:log] = ['value2']
        expect(provider).to receive(:zpool).with(:create, name, 'disk1', 'spare', 'value1', 'log', 'value2')
        provider.create
      end
    end

    context 'when creating mirrors for a zpool' do
      it "executes 'create' for a single group of mirrored devices" do
        resource[:mirror] = ['disk1 disk2']
        expect(provider).to receive(:zpool).with(:create, name, 'mirror', 'disk1', 'disk2')
        provider.create
      end

      it "repeats the 'mirror' keyword between groups of mirrored devices" do
        resource[:mirror] = ['disk1 disk2', 'disk3 disk4']
        expect(provider).to receive(:zpool).with(:create, name, 'mirror', 'disk1', 'disk2', 'mirror', 'disk3', 'disk4')
        provider.create
      end
    end

    describe 'when creating raidz for a zpool' do
      it "executes 'create' for a single raidz group" do
        resource[:raidz] = ['disk1 disk2']
        expect(provider).to receive(:zpool).with(:create, name, 'raidz1', 'disk1', 'disk2')
        provider.create
      end

      it "execute 'create' for a single raidz2 group" do
        resource[:raidz] = ['disk1 disk2']
        resource[:raid_parity] = 'raidz2'
        expect(provider).to receive(:zpool).with(:create, name, 'raidz2', 'disk1', 'disk2')
        provider.create
      end

      it "repeats the 'raidz1' keyword between each group of raidz devices" do
        resource[:raidz] = ['disk1 disk2', 'disk3 disk4']
        expect(provider).to receive(:zpool).with(:create, name, 'raidz1', 'disk1', 'disk2', 'raidz1', 'disk3', 'disk4')
        provider.create
      end
    end
  end

  context '#delete' do
    it 'calls zpool with destroy and the pool name' do
      expect(provider).to receive(:zpool).with(:destroy, name)
      provider.destroy
    end
  end

  context '#exists?' do
    it 'gets the current pool' do
      allow(provider).to receive(:current_pool).and_return(pool: 'somepool')
      expect(provider).to receive(:current_pool)
      provider.exists?
    end

    it 'returns false if the current_pool is absent' do
      allow(provider).to receive(:current_pool).and_return(pool: :absent)
      expect(provider).to receive(:current_pool)
      expect(provider).not_to be_exists
    end

    it 'returns true if the current_pool has values' do
      allow(provider).to receive(:current_pool).and_return(pool: name)
      expect(provider).to receive(:current_pool)
      expect(provider).to be_exists
    end
  end
end
