# AmoveoMinerGpuCudaLinux

## Original code

https://github.com/Mandelhoff/AmoveoMinerGpuCuda

## How to build

```
sh build.sh
```

## What I changed from original code

1. Add build.sh
2. Copy `main.cpp` to `main.cu`
3. Move `PoolApi` class inline in `main.cu`
4. Replace `SHA256_CTX` by `SHA256_CTXX`
    - ...ugly solution!
5. Some tiny changes
