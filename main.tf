provider "azurerm" {
  version = "~> 2.15"
  features {}
  #subscription_id = "${var.subscription_id}"
  #client_id = "${var.client_id}"
  #client_secret = "${var.client_secret}"
  #tenant_id = "${var.tenant_id}"
}

variable "azurerm_resource_group" {
  type = string
  description = "Resource Group to Add Network and VM on"
  default = "aharness-rg"
}

resource "random_string" "password" {
  length = 16
  special = true
  override_special = "_"
}

#resource "azurerm_resource_group" "group" {
#  name = "test-rg"
#  location = "centralus"
#}

# Create virtual network
resource "azurerm_virtual_network" "myterraformnetwork" {
    name                = "myVnet"
    address_space       = ["10.0.0.0/16"]
    location            = "centralus"
    resource_group_name = var.azurerm_resource_group
}

# Create subnet
resource "azurerm_subnet" "myterraformsubnet" {
    name                 = "mySubnet"
    virtual_network_name = azurerm_virtual_network.myterraformnetwork.name
    address_prefix       = "10.0.1.0/24"
    #network_security_group_id = "${azurerm_network_security_group.myterraformnsg.id}"
    resource_group_name = var.azurerm_resource_group
}

# Create public IPs
resource "azurerm_public_ip" "myterraformpublicip" {
    name                         = "myPublicIP4"
    location                     = "centralus"
    resource_group_name          = var.azurerm_resource_group
    allocation_method            = "Dynamic"

    #depends_on = [azurerm_resource_group.group]
}

# Create Network Security Group and rule
resource "azurerm_network_security_group" "myterraformnsg" {
    name                = "myNetworkSecurityGroup"
    location            = "centralus"
    resource_group_name = var.azurerm_resource_group

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
}

resource "azurerm_network_interface" "nic" {
  name = "mharen-test"
  location = "centralus"
  resource_group_name = var.azurerm_resource_group
  #network_security_group_id     = "${azurerm_network_security_group.myterraformnsg.id}"

  ip_configuration {
    name                          = "private_ip_address"
    subnet_id                     = azurerm_subnet.myterraformsubnet.id
    private_ip_address_allocation = "dynamic"
    public_ip_address_id          = azurerm_public_ip.myterraformpublicip.id
  }
}

resource "azurerm_virtual_machine" "vm" {
  name = "tf-test"
  location = "centralus"
  resource_group_name = var.azurerm_resource_group
  network_interface_ids = [azurerm_network_interface.nic.id]
  vm_size = "Standard_B1s"
  delete_os_disk_on_termination = true

  storage_os_disk {
    name = "winrm-test"
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
    admin_password = random_string.password.result
  }

  os_profile_windows_config {
    provision_vm_agent = true
    winrm = { protocol = "http" }
  }
}

resource "null_resource" "cluster" {
  # Changes to any instance of the cluster requires re-provisioning
  triggers {
    provision_trigger = uuid()
  }

  provisioner "remote-exec" {
    inline = ["powershell.exe echo foo > D:\\myfile.txt"]
  #on_failure = "continue"
  # Bootstrap script can run on any instance of the cluster
  # So we just choose the first in this case
  connection {
    type = "winrm"
    host = data.azurerm_public_ip.myterraformpublicip.ip_address
    port = 5985
    user = "deploy"
    password = random_string.password.result
    timeout = "10m"
    https = false
    insecure = true
    use_ntlm = false
  }

  }
}
#"commandToExecute": "powershell.exe echo foo > D:\\myfile_extension.txt;w32tm /config /manualpeerlist:\"REDACTED\";w32tm /config /update;net stop w32time;net start w32time;w32tm /resync; ((Get-Content -path 'C:\\chef\\client.rb' -Raw) -replace 'AWSRing1', '"${azurerm_virtual_machine.vm.name}tf"') | Set-Content -Path 'C:\\chef\\client.rb';cd C:\\opscode\\chef\\bin;.\\chef-client.bat --chef-license accept-silent;chef-service-manager -a start;exit 0"

resource "azurerm_virtual_machine_extension" "timefix" {
  name     = azurerm_virtual_machine.vm.name
  location = "centralus"
  resource_group_name = var.azurerm_resource_group
  virtual_machine_name = azurerm_virtual_machine.vm.name
  publisher = "Microsoft.Compute"
  type =  "CustomScriptExtension"
  type_handler_version = "1.9"

  settings = <<SETTINGS
    {
      "commandToExecute": "powershell.exe echo foo > D:\\myfile_extension.txt;exit 0"
    }
SETTINGS
}

data "azurerm_public_ip" "myterraformpublicip" {
  name                = azurerm_public_ip.myterraformpublicip.name
  resource_group_name = var.azurerm_resource_group
  #depends_on = "[azurerm_public_ip.myterraformpublicip,]"
}

  
output "vm_ip_address" {
  value = azurerm_network_interface.nic.private_ip_address
}

output "vm_username" {
  value = "deploy"
}

output "vm_password" {
  value = random_string.password.result
}
