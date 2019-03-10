provider "azurerm" {
  version = "~> 1.23"
  #subscription_id = "${var.subscription_id}"
  #client_id = "${var.client_id}"
  #client_secret = "${var.client_secret}"
  #tenant_id = "${var.tenant_id}"
}

variable "azurerm_resource_group" {
  type = "string"
  description = "Resource Group to Add Network and VM on"
}

resource "random_string" "password" {
  length = 16
  special = true
  override_special = "_"
}

#resource "azurerm_resource_group" "group" {
#  name = "terraform-sandbox"
#  location = "eastus"
#}

# Create virtual network
resource "azurerm_virtual_network" "myterraformnetwork" {
    name                = "myVnet"
    address_space       = ["10.0.0.0/16"]
    location            = "centralus"
    resource_group_name = "${var.azurerm_resource_group}"

    tags {
        environment = "Terraform Demo"
    }
}

# Create subnet
resource "azurerm_subnet" "myterraformsubnet" {
    name                 = "mySubnet"
    resource_group_name  = "${var.azurerm_resource_group}"
    virtual_network_name = "${azurerm_virtual_network.myterraformnetwork.name}"
    address_prefix       = "10.0.1.0/24"
    network_security_group_id = "${azurerm_network_security_group.myterraformnsg.id}"
}

# Create public IPs
resource "azurerm_public_ip" "myterraformpublicip" {
    name                         = "myPublicIP2"
    location                     = "centralus"
    resource_group_name          = "${var.azurerm_resource_group}"
    public_ip_address_allocation = "dynamic"

    tags {
        environment = "Terraform Demo"
    }
}

# Create Network Security Group and rule
resource "azurerm_network_security_group" "myterraformnsg" {
    name                = "myNetworkSecurityGroup"
    location            = "centralus"
    resource_group_name = "${var.azurerm_resource_group}"

    security_rule {
        name                       = "RDP"
        priority                   = 1001
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "3389"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
    }

  security_rule {
        name                       = "WinRM"
        priority                   = 998
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "5985-5986"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
    }


    tags {
        environment = "Terraform Demo"
    }
}

resource "azurerm_network_interface" "nic" {
  name = "mharen-test"
  location = "centralus"
  resource_group_name = "${var.azurerm_resource_group}"
  network_security_group_id     = "${azurerm_network_security_group.myterraformnsg.id}"

  ip_configuration {
    name                          = "private_ip_address"
    subnet_id                     = "${azurerm_subnet.myterraformsubnet.id}"
    private_ip_address_allocation = "dynamic"
    public_ip_address_id          = "${azurerm_public_ip.myterraformpublicip.id}"
  }
}

resource "azurerm_virtual_machine" "vm" {
  name = "tf-test"
  location = "centralus"
  resource_group_name = "${var.azurerm_resource_group}"
  network_interface_ids = ["${azurerm_network_interface.nic.id}"]
  vm_size = "Standard_B1s"
  delete_os_disk_on_termination = true

  storage_os_disk {
    name = "mharen-test"
    caching = "ReadWrite"
    create_option = "FromImage"
    managed_disk_type = "Premium_LRS"
  }

  storage_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer = "WindowsServer"
    sku = "2016-Datacenter"
    version = "latest"
  }

  os_profile {
    computer_name= "tf-test"
    admin_username = "deploy"
    admin_password = "${random_string.password.result}"
  }

  os_profile_windows_config {
    provision_vm_agent = true
    winrm = { protocol = "http" }
  }
}

variable provision_trigger {default="2"}

resource "null_resource" "cluster" {
  # Changes to any instance of the cluster requires re-provisioning
  triggers {
    provision_trigger = "${var.provision_trigger}"
  }

  # Bootstrap script can run on any instance of the cluster
  # So we just choose the first in this case
  connection {
    type = "winrm"
    host = "${data.azurerm_public_ip.myterraformpublicip.ip_address}"
    port = 5985
    user = "deploy"
    password = "${random_string.password.result}"
    timeout = "10m"
    https = false
    insecure = true
    use_ntlm = false
  }

  provisioner "remote-exec" {
    inline = ["mkdir c:\\test & echo foo > c:\\test\\test.txt"]
  }
}

data "azurerm_public_ip" "myterraformpublicip" {
  name                = "${azurerm_public_ip.myterraformpublicip.name}"
  resource_group_name = "${var.azurerm_resource_group}"
}

  
output "vm_ip_address" {
  value = "${azurerm_network_interface.nic.private_ip_address}"
}

output "vm_username" {
  value = "deploy"
}

output "vm_password" {
  value = "${random_string.password.result}"
}
