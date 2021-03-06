#
# Author:: Kurt Yoder (ktyopscode@yoderhome.com)
# Copyright:: Copyright (c) 2008-2016 Chef Software, Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

Ohai.plugin(:Filesystem) do
  provides "filesystem"

  collect_data(:solaris2) do
    fs = Mash.new

    # Grab filesystem data from df
    so = shell_out("df -Pka")
    so.stdout.lines do |line|
      case line
      when /^Filesystem\s+kbytes/
        next
      when /^(.+?)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+\%)\s+(.+)$/
        filesystem = $1
        fs[filesystem] = Mash.new
        fs[filesystem][:kb_size] = $2
        fs[filesystem][:kb_used] = $3
        fs[filesystem][:kb_available] = $4
        fs[filesystem][:percent_used] = $5
        fs[filesystem][:mount] = $6
      end
    end

    # Grab file system type from df (must be done separately)
    so = shell_out("df -na")
    so.stdout.lines do |line|
      next unless line =~ /^(.+?)\s*: (\S+)\s*$/
      mount = $1
      fs.each do |filesystem, fs_attributes|
        next unless fs_attributes[:mount] == mount
        fs[filesystem][:fs_type] = $2
      end
    end

    # Grab mount information from /bin/mount
    so = shell_out("mount")
    so.stdout.lines do |line|
      next unless line =~ /^(.+?) on (.+?) (.+?) on (.+?)$/
      filesystem = $2
      fs[filesystem] = Mash.new unless fs.has_key?(filesystem)
      fs[filesystem][:mount] = $1
      fs[filesystem][:mount_time] = $4 # $4 must come before "split", else it becomes nil
      fs[filesystem][:mount_options] = $3.split("/")
    end

    # Grab any zfs data from "zfs get"
    zfs = Mash.new
    # ohai.plugin[:filesystem][:zfs_properties] = 'used'
    # ohai.plugin[:filesystem][:zfs_properties] = ['mountpoint', 'creation', 'available', 'used']
    zfs_get = "zfs get -p -H "
    if configuration(:zfs_properties).nil? || configuration(:zfs_properties).empty?
      zfs_get << "all"
    else
      zfs_get << [configuration(:zfs_properties)].join(",")
    end
    so = shell_out(zfs_get)
    so.stdout.lines do |line|
      next unless line =~ /^([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)$/
      filesystem = $1
      zfs[filesystem] = Mash.new unless zfs.has_key?(filesystem)
      zfs[filesystem][:values] = Mash.new unless zfs[filesystem].has_key?("values")
      zfs[filesystem][:sources] = Mash.new unless zfs[filesystem].has_key?("sources")
      zfs[filesystem][:values][$2] = $3
      zfs[filesystem][:sources][$2] = $4.chomp
    end

    zfs.each do |filesystem, attributes|
      fs[filesystem] = Mash.new unless fs.has_key?(filesystem)
      fs[filesystem][:fs_type] = "zfs"
      fs[filesystem][:mount] = attributes[:values][:mountpoint] if attributes[:values].has_key?("mountpoint")
      fs[filesystem][:zfs_values] = attributes[:values]
      fs[filesystem][:zfs_sources] = attributes[:sources]
      # find all zfs parents
      parents = filesystem.split("/")
      zfs_parents = []
      (0..parents.length - 1).to_a.each do |parent_indexes|
        next_parent = parents[0..parent_indexes].join("/")
        zfs_parents.push(next_parent)
      end
      zfs_parents.pop
      fs[filesystem][:zfs_parents] = zfs_parents
      fs[filesystem][:zfs_zpool] = (zfs_parents.length == 0)
    end

    # Set the filesystem data
    filesystem fs
  end
end
