provider "azurerm" {
  version = "~> 1.21"
  #subscription_id = "${var.subscription_id}"
  #client_id = "${var.client_id}"
  #client_secret = "${var.client_secret}"
  #tenant_id = "${var.tenant_id}"
}

resource "random_string" "password" {
  length = 16
  special = true
  override_special = "_"
}

resource "azurerm_resource_group" "group" {
  name = "terraform-sandbox"
  location = "eastus"
}

resource "azurerm_network_interface" "nic" {
  name = "mharen-test"
  location = "${azurerm_resource_group.group.location}"
  resource_group_name = "${azurerm_resource_group.group.name}"

  ip_configuration {
    name = "private_ip_address"
    subnet_id = "${var.subnet_id}"
    private_ip_address_allocation = "dynamic"
  }
}

resource "azurerm_virtual_machine" "vm" {
  name = "tf-test"
  location = "${azurerm_resource_group.group.location}"
  resource_group_name = "${azurerm_resource_group.group.name}"
  network_interface_ids = ["${azurerm_network_interface.nic.id}"]
  vm_size = "Standard_F2S"
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
    host = "${azurerm_network_interface.nic.private_ip_address}"
    port = 5985
    user = "deploy"
    password = "${random_string.password.result}"
    timeout = "10m"
    https = false
    insecure = true
    use_ntlm = false
  }

  provisioner "remote-exec" {
    inline = ["echo foo > c:\\test.txt"]
  }
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
