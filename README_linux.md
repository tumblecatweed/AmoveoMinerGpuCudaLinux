# AmoveoMinerGpuCudaLinux

## Current version

`v1.0.0.7`

## Original code

https://github.com/Mandelhoff/AmoveoMinerGpuCuda

## Dependencies

CUDA 9.1 or later

```
sudo apt-get install libcpprest-dev libncurses5-dev libssl-dev unixodbc-dev g++ git
```

## How to install CUDA

```
wget http://developer.download.nvidia.com/compute/cuda/repos/ubuntu1604/x86_64/cuda-repo-ubuntu1604_9.1.85-1_amd64.deb
sudo apt-key adv —fetch-keys http://developer.download.nvidia.com/compute/cuda/repos/ubuntu1604/x86_64/7fa2af80.pub
sudo dpkg -i cuda-repo-ubuntu1604_9.1.85-1_amd64.deb
sudo apt update
sudo apt install cuda -y
```

Add these lines to the end of `.bashrc`

```
export PATH="/usr/local/cuda/bin:$PATH"
export LD_LIBRARY_PATH="/usr/local/cuda/lib64:$LD_LIBRARY_PATH"
```

## How to build

```
git clone https://github.com/tumblecatweed/AmoveoMinerGpuCudaLinux.git
cd ./AmoveoMinerGpuCudaLinux
sh build.sh
```

## How to run

See original README.md
