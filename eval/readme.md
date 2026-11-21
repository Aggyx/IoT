# Ton home a un quota : mets les boxes et les VMs dans goinfre
export VAGRANT_HOME=/goinfre/$USER/vagrant.d
VBoxManage setproperty machinefolder /goinfre/$USER/vms

cd IoT/eval
IOT_KEYBOARD=fr vagrant up    # ou es, us...