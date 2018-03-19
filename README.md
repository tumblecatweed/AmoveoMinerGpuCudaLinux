# AmoveoMinerGpuCudaLinux

## Announcement

This fork is no longer maintained.

Please use original [AmoveoMinerGpuCuda](https://github.com/Mandelhoff/AmoveoMinerGpuCuda).

## About

Amoveo Cryptocurrency Miner for Gpu work to be used with [AmoveoPool2.com](http://AmoveoPool2.com) or [amoveo mining pool](https://github.com/zack-bitcoin/amoveo-mining-pool). This version is a Linux port of [original windows miner](https://github.com/Mandelhoff/AmoveoMinerGpuCuda).

Tested Gpu Speeds:

* Tesla V100: 3900 Mh/s  - Suggested BlockSize: 1024, Numblocks: 64
* Tesla P100: 1920 Mh/s  - Suggested BlockSize: 192, Numblocks: 168
* GTX1080 TI: 2200 Mh/s  - Suggested BlockSize: 96, Numblocks: 168
* GTX1060 6GB: 901 Mh/s  - Suggested BlockSize: 64
* GTX1050:    430 Mh/s  - Suggested BlockSize: 64
* Tesla K80:  301 Mh/s  - Suggested BlockSize: 128
* 750TI:      238 Mh/s  - Suggested BlockSize: 32

Default BlockSize is 64.
Default NumBlocks is 96.
Default SuffixMax is 65536.
* Try various BlockSize setting values. Optimal setting for BlockSize is very personal to your system. Try BlockSize values like 96, 64, 32, or 128. A higher BlockSize is almost always better, but too high will crash the miner.
* If you get too much OS lag, reduce the SuffixMax setting (at the cost of a some hash rate).
* If your Memory Controller Load is constantly at 100%, you may want to try lowering your NumBlocks.

Best Settings from My Tests:
* Gtx1060: BlockSize=64, NumBlocks=96
* Gtx1050: BlockSize=64, NumBlocks=90
* Tesla K80: BlockSize=128, NumBlocks=128
* 750Ti: BlockSize=32, NumBlocks=64

### Dependencies

CUDA 9.1 or later

```
sudo apt-get install libcpprest-dev libncurses5-dev libssl-dev unixodbc-dev g++ git
```

### Install CUDA9.1

```
wget http://developer.download.nvidia.com/compute/cuda/repos/ubuntu1604/x86_64/cuda-repo-ubuntu1604_9.1.85-1_amd64.deb
sudo apt-key adv —fetch-keys http://developer.download.nvidia.com/compute/cuda/repos/ubuntu1604/x86_64/7fa2af80.pub
sudo dpkg -i cuda-repo-ubuntu1604_9.1.85-1_amd64.deb
sudo apt update
sudo apt install cuda -y
```

Add these lines to the end of `.bashrc`

```
export CUDA_HOME=/usr/local/cuda
export PATH="/usr/local/cuda/bin:$PATH"
export LD_LIBRARY_PATH="/usr/local/cuda/lib64:$LD_LIBRARY_PATH"
```

### Build

```
git clone https://github.com/tumblecatweed/AmoveoMinerGpuCudaLinux.git
cd ./AmoveoMinerGpuCudaLinux
sh build.sh
```

### Run

Example Usage:
```
./AmoveoMinerGpuCudaLinux BPA3r0XDT1V8W4sB14YKyuu/PgC6ujjYooVVzq1q1s5b6CAKeu9oLfmxlplcPd+34kfZ1qx+Dwe3EeoPu0SpzcI=
```

Advanced Usage Template:
```
./AmoveoMinerGpuCudaLinux <Base64AmoveoAddress> <CudaDeviceId> <BlockSize> <NumBlocks> <RandomSeed> <SuffixMax> <PoolUrl> <PoolType>
```
* CudaDeviceId is optional an defaults to 0.
* BlockSize is optional and defaults to 256.
* NumBlocks is optional and defaults to 65536
* RandomSeed is optional. Set this if you want multiple miners using the same address to avoid nonce collisions.
* SuffixMax optional and defaults to 65536. Do NOT use anything higher than 65536. Lower numbers reduce OS lag and will reduce hash rate by a few percent.
* PoolUrl is optional and defaults to http://amoveopool2.com/work
* PoolType is optional. Specify 0 (for amoveopool.com) or 1 (for amoveo original mining pool). Default is 0.


Donations are welcome:

To linux port author (catweed):
* VEO: BOPvbgrso8GakBw2Xxkc1A2lt0OiKg/JqjBuCPfP0bTI/djsM9lgp/8ZMmJgPs/aDlxQL2dT+PYfEywsaRthrmE=
* ETH: 0x07D47A1C6de0FD4E1608641f27a156b4692Be72e

To original windows miner author (Mandel):
* VEO: BPA3r0XDT1V8W4sB14YKyuu/PgC6ujjYooVVzq1q1s5b6CAKeu9oLfmxlplcPd+34kfZ1qx+Dwe3EeoPu0SpzcI=
* ETH: 0x74e0aF0522024f2dd94F0fb9B82d13782ECCaaF5
