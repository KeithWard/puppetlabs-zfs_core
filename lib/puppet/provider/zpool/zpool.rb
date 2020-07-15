Puppet::Type.type(:zpool).provide(:zpool) do
  desc 'Provider for zpool.'

  commands zpool: 'zpool'

  # NAME    SIZE  ALLOC   FREE    CAP  HEALTH  ALTROOT
  def self.instances
    zpool(:list, '-H').split("\n").map do |line|
      name, _size, _alloc, _free, _cap, _health, _altroot = line.split(%r{\s+})
      new(name: name, ensure: :present)
    end
  end

  def get_zpool_property(prop)
    zpool(:get, prop, @resource[:name]).split("\n").reverse.map { |line|
      name, _property, value, _source = line.split("\s")
      value if name == @resource[:name]
    }.shift
  end

  def process_zpool_data(pool_array)
    if pool_array == []
      return Hash.new(:absent)
    end
    # get the name and get rid of it
    pool = {}
    pool[:pool] = pool_array[0]
    pool_array.shift

    tmp = []

    # order matters here :(
    pool_array.reverse_each do |value|
      sym = nil
      case value
      when 'spares'
        sym = :spare
      when 'logs'
        sym = :log
      when %r{^mirror|^raidz1|^raidz2}
        sym = (value =~ %r{^mirror}) ? :mirror : :raidz
        pool[:raid_parity] = 'raidz2' if value =~ %r{^raidz2}
      else
        vdev = if File.symlink?(value) and File.readlink(value) !~ %r{dm-[0-9]+$}
                 File.expand_path(File.readlink(value), File.dirname(value))
               else
                 value
               end

        # get full drive name if the value is a partition (Linux only)
        tmp << if Facter.value(:kernel) == 'Linux' && %r{(\/dev\/[a-z]{3}(1))$} =~ vdev
                 vdev.chomp(Regexp.last_match(2))
               elsif Facter.value(:kernel) == 'Linux' && %r{(\/dev\/nvme[0-9n]+)p1} =~ vdev
                 Regexp.last_match(1)
               else
                 vdev
               end
        sym = :disk if value == pool_array.first
      end

      if sym
        pool[sym] = (pool[sym]) ? pool[sym].unshift(tmp.reverse.join(' ')) : [tmp.reverse.join(' ')]
        tmp.clear
      end
    end

    pool
  end

  # rubocop:disable Style/AccessorMethodName
  # rubocop:disable Style/NumericPredicate
  def get_pool_data
    # https://docs.oracle.com/cd/E19082-01/817-2271/gbcve/index.html
    # we could also use zpool iostat -v mypool for a (little bit) cleaner output
    zpool_opts = case Facter.value(:kernel)
                 # use full device names ("-P") on Linux/ZOL to prevent
                 # mismatches between creation and display paths:
                 when 'Linux'
                   '-P'
                 else
                   ''
                 end
    out = execute("zpool status #{zpool_opts} #{@resource[:pool]}", failonfail: false, combine: false)
    zpool_data = out.lines.select { |line| line.index("\t") == 0 }.map { |l| l.strip.split("\s")[0] }
    zpool_data.shift
    zpool_data
  end

  def current_pool
    @current_pool = process_zpool_data(get_pool_data) unless defined?(@current_pool) && @current_pool
    @current_pool
  end

  def flush
    @current_pool = nil
  end

  # Adds log and spare
  def build_named(name)
    prop = @resource[name.to_sym]
    if prop
      [name] + prop.map { |p| p.split(' ') }.flatten
    else
      []
    end
  end

  # query for parity and set the right string
  def raidzarity
    (@resource[:raid_parity]) ? @resource[:raid_parity] : 'raidz1'
  end

  # handle mirror or raid
  def handle_multi_arrays(prefix, array)
    array.map { |a| [prefix] + a.split(' ') }.flatten
  end

  # builds up the vdevs for create command
  def build_vdevs
    disk = @resource[:disk]
    mirror = @resource[:mirror]
    raidz = @resource[:raidz]

    if disk
      disk.map { |d| d.split(' ') }.flatten
    elsif mirror
      handle_multi_arrays('mirror', mirror)
    elsif raidz
      handle_multi_arrays(raidzarity, raidz)
    end
  end

  def add_pool_properties
    properties = []
    [:ashift, :autoexpand, :failmode].each do |property|
      if (value = @resource[property]) && value != ''
        properties << '-o' << "#{property}=#{value}"
      end
    end
    properties
  end

  def create
    zpool(*([:create] + add_pool_properties + [@resource[:pool]] + build_vdevs + build_named('spare') + build_named('log')))
  end

  def destroy
    zpool :destroy, @resource[:pool]
  end

  def exists?
    if current_pool[:pool] == :absent
      false
    else
      true
    end
  end

  [:disk, :mirror, :raidz, :log, :spare].each do |field|
    define_method(field) do
      current_pool[field]
    end

    # rubocop:disable Style/SignalException
    define_method(field.to_s + '=') do |should|
      fail "zpool #{field} can't be changed. should be #{should}, currently is #{current_pool[field]}"
    end
  end

  [:autoexpand, :failmode].each do |field|
    define_method(field) do
      get_zpool_property(field)
    end

    define_method(field.to_s + '=') do |should|
      zpool(:set, "#{field}=#{should}", @resource[:name])
    end
  end

  # Borrow the code from the ZFS provider here so that we catch and return '-'
  # as ashift is linux only.
  # see lib/puppet/provider/zfs/zfs.rb

  PARAMETER_UNSET_OR_NOT_AVAILABLE = '-'.freeze

  define_method(:ashift) do
    begin
      get_zpool_property(:ashift)
    rescue
      PARAMETER_UNSET_OR_NOT_AVAILABLE
    end
  end

  define_method('ashift=') do |should|
    begin
      zpool(:set, "ashift=#{should}", @resource[:name])
    rescue
      PARAMETER_UNSET_OR_NOT_AVAILABLE
    end
  end
end
