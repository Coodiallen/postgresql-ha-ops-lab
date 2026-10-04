Vagrant.configure("2") do |config|
  config.vm.box = "bento/ubuntu-24.04"
  config.vm.box_version = "202508.03.0"

  config.vm.synced_folder ".", "/vagrant", disabled: true

  config.vagrant.plugins = "vagrant-libvirt"

  nodes = {
    "pg01"    => { ip: "192.168.60.11", memory: 1536, cpus: 2 },
    "pg02"    => { ip: "192.168.60.12", memory: 1536, cpus: 2 },
    "pg03"    => { ip: "192.168.60.13", memory: 1536, cpus: 2 },
    "proxy01" => { ip: "192.168.60.21", memory: 512,  cpus: 1 },
    "proxy02" => { ip: "192.168.60.22", memory: 512,  cpus: 1 },
    "ops01"   => { ip: "192.168.60.30", memory: 2048, cpus: 2 }
  }

  nodes.each do |name, node|
    config.vm.define name do |machine|
      machine.vm.hostname = name

      machine.vm.network "private_network",
        ip: node[:ip],
        auto_config: true,
        libvirt__network_name: "pg-lab-net",
        libvirt__always_destroy: false

      machine.vm.provider :libvirt do |libvirt|
        libvirt.memory = node[:memory]
        libvirt.cpus = node[:cpus]

        libvirt.storage_pool_name = "postgresql-lab"

        libvirt.management_network_name = "vagrant-libvirt"
        libvirt.management_network_address = "192.168.121.0/24"
        libvirt.management_network_mode = "nat"
        libvirt.management_network_autostart = true

        libvirt.graphics_type = "none"
      end
    end
  end
end
