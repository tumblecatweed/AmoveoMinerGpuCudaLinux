#define VERSION_STRING "1.0.0.7"
#define TOOL_NAME "AmoveoMinerGpuCuda"

#include <iostream>
#include <chrono>
#include <cmath>
#include <thread>
#include <iomanip>
#include <string>
#include <cassert>

#include <vector>
#include <random>
#include <climits>
#include <algorithm>
#include <functional>

#include "cuda_runtime.h"
#include "device_launch_parameters.h"

#include "sha256.cuh"
#include "stdlib.h"

#include <future>
#include <numeric>
#include <chrono>

#include <cpprest/asyncrt_utils.h>

#include "poolApi.h"
#include "base64.h"

#include "unistd.h"

using namespace std;
using namespace std::chrono;

using namespace utility;									// Common utilities like string conversions

#define FETCH_WORK_INTERVAL_MS 9000
#define SHOW_INTERVAL_MS 4000

int gElapsedMilliSecMax = FETCH_WORK_INTERVAL_MS;

//#define POOL_URL "http://localhost:32371/work"	// local pool
#define POOL_URL "http://amoveopool2.com/work"
#define MINER_ADDRESS "BOPvbgrso8GakBw2Xxkc1A2lt0OiKg/JqjBuCPfP0bTI/djsM9lgp/8ZMmJgPs/aDlxQL2dT+PYfEywsaRthrmE="
#define DEFAULT_DEVICE_ID 0

string gMinerPublicKeyBase64(MINER_ADDRESS);
string gPoolUrl(POOL_URL);
string_t gPoolUrlW;
int gDevicdeId = DEFAULT_DEVICE_ID;
int gPoolType = 0; // 0: amoveopool, 1: original pool

PoolApi gPoolApi;
WorkData gWorkData;
std::mutex mutexWorkData;


uint64_t gTotalNonce = 0;

// First timestamp when program starts
static std::chrono::high_resolution_clock::time_point t1;

// Last timestamp we printed debug info
static std::chrono::high_resolution_clock::time_point t_last_updated;
static std::chrono::high_resolution_clock::time_point t_last_work_fetch;


__device__ bool checkResult(unsigned char* h, size_t diff) {
    unsigned int x = 0;
    unsigned int z = 0;
    for (int i = 0; i < 31; i++) {
      if (h[i] == 0) {
        x += 8;
        continue;
      }
      else if (h[i] < 2) {
        x += 7;
        z = h[i+1];
      }
      else if (h[i] < 4) {
        x += 6;
        z = (h[i+1] / 2) + ((h[i] % 2) * 128);
      }
      else if (h[i] < 8) {
        x += 5;
        z = (h[i+1] / 4) + ((h[i] % 4) * 64);
      }
      else if (h[i] < 16) {
        x += 4;
        z = (h[i+1] / 8) + ((h[i] % 8) * 32);
      }
      else if (h[i] < 32) {
        x += 3;
        z = (h[i+1] / 16) + ((h[i] % 16) * 16);
      }
      else if (h[i] < 64) {
        x += 2;
        z = (h[i+1] / 32) + ((h[i] % 32) * 8);
      }
      else if (h[i] < 128) {
        x += 1;
        z = (h[i+1] / 64) + ((h[i] % 64) * 4);
      }
      else {
        z = (h[i+1] / 128) + ((h[i] % 128) * 2);
      }
      break;
    }
    return(((256 * x) + z) >= diff);
}

#define SUFFIX_MAX 65536

__global__ void sha256_kernel(unsigned char * out_nonce, int *out_found, const SHA256_CTX * in_ctx, uint64_t nonceOffset, int shareDiff, int suffixMax)
{
	__shared__ SHA256_CTX ctxShared;
	__shared__ int diff;
	__shared__ uint64_t nonceOff;

	// If this is the first thread of the block, init the input string in shared memory
	if (threadIdx.x == 0) {
		memcpy(&ctxShared, in_ctx, 0x70);
		diff = shareDiff;
		nonceOff = nonceOffset;
	}
	__syncthreads(); // Ensure the input string has been written in SMEM

	unsigned int threadIndex = threadIdx.x;
	uint64_t currentBlockIdx = blockIdx.x * blockDim.x + threadIdx.x + nonceOff;

	unsigned char shaResult[32];
	SHA256_CTX ctxReuse;
	memcpy(&ctxReuse, &ctxShared, 0x70);
	sha256_update(&ctxReuse, (BYTE*)&currentBlockIdx, 6);
	sha256_updateAmoveoSpecial(&ctxReuse);

	SHA256_CTX ctxTmp;
	int nonceSuffix = 0;
	for (nonceSuffix = 0; nonceSuffix < suffixMax; nonceSuffix++) {
		memcpy(&ctxTmp, &ctxReuse, 0x70);
		sha256_finalAmoveo(&ctxTmp, (BYTE*)&nonceSuffix, shaResult);
		if (checkResult(shaResult, diff) && atomicExch(out_found, 1) == 0) {
			memcpy(out_nonce, &currentBlockIdx, 6);
			memcpy(out_nonce + 6, &nonceSuffix, 2);
			return;
		}
	}
}

__global__ void sha256Init_kernel(unsigned char * out_ctx, unsigned char * bhash, unsigned char * noncePart, int diff)
{
	SHA256_CTX ctx;
	unsigned char bhashLocal[32];
	unsigned char nonceLocal[15];

	memcpy(bhashLocal, bhash, 32);
	memcpy(nonceLocal, noncePart, 15);

	sha256_init(&ctx);
	sha256_update(&ctx, bhashLocal, 32);
	sha256_update(&ctx, nonceLocal, 15);
	memcpy(out_ctx, &ctx, 0x70);
}


void pre_sha256() {
	checkCudaErrors(cudaMemcpyToSymbol(dev_k, host_k, sizeof(host_k), 0, cudaMemcpyHostToDevice));
}

// Prints a 32 bytes sha256 to the hexadecimal form filled with zeroes
void print_hash(const unsigned char* sha256) {
	for (size_t i = 0; i < 32; ++i) {
		std::cout << std::hex << std::setfill('0') << std::setw(2) << static_cast<int>(sha256[i]);
	}
	std::cout << std::dec << std::endl;
}

bool isTimeToGetNewWork()
{
	std::chrono::high_resolution_clock::time_point tNow = std::chrono::high_resolution_clock::now();
	std::chrono::duration<double, std::milli> lastWorkFetchInterval = tNow - t_last_work_fetch;
	if (lastWorkFetchInterval.count() > gElapsedMilliSecMax) {
		t_last_work_fetch = tNow;
		return true;
	}
	return false;
}

void print_state() {
	std::chrono::high_resolution_clock::time_point t2 = std::chrono::high_resolution_clock::now();

	std::chrono::duration<double, std::milli> last_show_interval = t2 - t_last_updated;
	if (last_show_interval.count() > SHOW_INTERVAL_MS) {
		t_last_updated = std::chrono::high_resolution_clock::now();
		std::chrono::duration<double, std::milli> span = t2 - t1;
		float ratio = span.count() / 1000;
		std::cout << std::fixed << static_cast<uint64_t>(gTotalNonce / ratio) << " h/s " << endl;
	}
}

static bool getwork_thread(std::seed_seq &seed)
{
	std::independent_bits_engine<std::default_random_engine, 32, uint32_t> randomBytesEngine(seed);

	unsigned char ctxBuf[0x70];

	unsigned char *d_bhash = nullptr;
	unsigned char *d_nonce = nullptr;
	cudaMalloc(&d_bhash, 32);
	cudaMalloc(&d_nonce, 15);
	unsigned char * outCtx = nullptr;
	cudaMalloc(&outCtx, 0x70);

	while (true)
	{
		WorkData workDataNew;
		gPoolApi.GetWork(gPoolUrlW, &workDataNew, gMinerPublicKeyBase64, gPoolType);

		// Check if new work unit is actually different than what we currently have
		if (memcmp(&gWorkData.bhash[0], &workDataNew.bhash[0], 32) != 0) {
			mutexWorkData.lock();
			std::generate(begin(gWorkData.nonce), end(gWorkData.nonce), std::ref(randomBytesEngine));
			gWorkData.bhash = workDataNew.bhash;
			gWorkData.blockDifficulty = workDataNew.blockDifficulty;
			gWorkData.shareDifficulty = workDataNew.shareDifficulty;

			cudaMemcpy(d_bhash, &gWorkData.bhash[0], 32, cudaMemcpyHostToDevice);
			cudaMemcpy(d_nonce, &gWorkData.nonce[0], 15, cudaMemcpyHostToDevice);

			sha256Init_kernel << < 1, 1 >> > (outCtx, d_bhash, d_nonce, gWorkData.blockDifficulty);

			cudaError_t err = cudaDeviceSynchronize();
			if (err != cudaSuccess) {
				std::cout << "getwork_thread Cuda Error: " << cudaGetErrorString(err) << std::endl;
				throw std::runtime_error("getwork_thread Device error");
			}

			cudaMemcpy(ctxBuf, outCtx, 0x70, cudaMemcpyDeviceToHost);
			//SHA256_CTX ctx;
			//memcpy(&ctx, outCtx, sizeof(SHA256_CTX));
			gWorkData.setCtx(ctxBuf);

			mutexWorkData.unlock();

			std::cout << "New Work ||" << "BDiff:" << gWorkData.blockDifficulty << " SDiff:" << gWorkData.shareDifficulty << endl;
		}
		else {
			// Even if new work is not available, shareDiff will likely change. Need to adjust, else will get a "low diff share" error.
			gWorkData.shareDifficulty = workDataNew.shareDifficulty;
		}

        usleep(2000000);
	}

	cudaFree(outCtx);
	cudaFree(d_bhash);
	cudaFree(d_nonce);
	return true;
}

static void submitwork_thread(unsigned char * nonceSolution)
{
	gPoolApi.SubmitWork(gPoolUrlW, base64_encode(nonceSolution, 23), gMinerPublicKeyBase64);
	cout << "--- Found Share --- " << endl;
}

int gBlockSize = 64;
int gNumBlocks = 96;
int gSuffixMax = 65536;
std::string gSeedStr("ImAraNdOmStrInG");

int main(int argc, char* argv[])
{
	cout << TOOL_NAME << " v" << VERSION_STRING << endl;
	if (argc <= 1) {
		cout << "Example Template: " << endl;
		cout << argv[0] << " " << "<Base64AmoveoAddress>" << " " << "<CudaDeviceId>" << " " << "<BlockSize>" << " " << "<NumBlocks>" << " " << "<SeedString>" << " " << "<SuffixMax>" << " " << "<PoolUrl>" << "<PoolType>" << endl;

		cout << endl;
		cout << "Example Usage: " << endl;
		cout << argv[0] << " " << MINER_ADDRESS << endl;

		cout << endl;
		cout << "Advanced Example Usage: " << endl;
		cout << argv[0] << " " << MINER_ADDRESS << " " << DEFAULT_DEVICE_ID << " " << gBlockSize << " " << gNumBlocks << " " << "RandomSeed" << " " << "65536" << " " << POOL_URL << endl;

		cout << endl;
		cout << endl;
		cout << "CudaDeviceId is optional. Default CudaDeviceId is 0" << endl;
		cout << "BlockSize is optional. Default BlockSize is 64" << endl;
		cout << "NumBlocks is optional. Default NumBlocks is 96" << endl;
		cout << "RandomSeed is optional. No default." << endl;
		cout << "SuffixMax is optional. Default is 65536" << endl;
		cout << "PoolUrl is optional. Default PoolUrl is http://amoveopool.com/work" << endl;
		cout << "PoolType is optional. Specify 0 (for amoveopool.com) or 1 (for amoveo original pool). Default is 0" << endl;
		return -1;
	}
	if (argc >= 2) {
		gMinerPublicKeyBase64 = argv[1];
	}
	if (argc >= 3) {
		gDevicdeId = atoi(argv[2]);
	}
	if (argc >= 4) {
		gBlockSize = atoi(argv[3]);
	}
	if (argc >= 5) {
		gNumBlocks = atoi(argv[4]);
	}
	if (argc >= 6) {
		gSeedStr = argv[5];
	}
	if (argc >= 7) {
		gSuffixMax = atoi(argv[6]);
	}
	if (argc >= 8) {
		gPoolUrl = argv[7];
	}
	if (argc >= 9) {
		gPoolType = atoi(argv[8]);
	}

	gPoolUrlW.resize(gPoolUrl.length(), L' ');
	std::copy(gPoolUrl.begin(), gPoolUrl.end(), gPoolUrlW.begin());
	std::seed_seq seed(gSeedStr.begin(), gSeedStr.end());

	cudaDeviceProp deviceProp;
	cudaGetDeviceProperties(&deviceProp, gDevicdeId);
	cout << "GPU Device Properties:" << endl;
	cout << "maxThreadsDim: " << deviceProp.maxThreadsDim << endl;
	cout << "maxThreadsPerBlock: " << deviceProp.maxThreadsPerBlock << endl;
	cout << "maxGridSize: " << deviceProp.maxGridSize << endl;

	cudaSetDevice(gDevicdeId);
	cudaDeviceSetCacheConfig(cudaFuncCachePreferShared);
	//cudaDeviceSetCacheConfig(cudaFuncCachePreferNone);

	unsigned char localCtx[0x70];
	// Input string for the device
	SHA256_CTX * d_ctx = nullptr;
	// Output string by the device read by host
	unsigned char *g_out = nullptr;
	int *g_found = nullptr;

	cudaMalloc(&d_ctx, sizeof(SHA256_CTX)); // SHA256_CTX ctx to be used

	cudaMalloc(&g_out, 8); // partial nonce - last 8 bytes
	cudaMalloc(&g_found, 4); // "found" success flag

	future<bool> getWorkThread = std::async(std::launch::async, getwork_thread, std::ref(seed));


	// Assuming bhash and nonce are fixed size, so dynamic_shared_size should never change across work units
//	size_t dynamic_shared_size = sizeof(SHA256_CTX) * gBlockSize + sizeof(SHA256_CTX) + sizeof(uint64_t) + sizeof(int);// +(64 * gBlockSize);
//	std::cout << "Shared memory is " << dynamic_shared_size << "B" << std::endl;

	const uint64_t blocksPerKernel = gNumBlocks * gBlockSize;
	const uint64_t hashesPerKernel = blocksPerKernel * gSuffixMax;
	cout << "blockSize: " << gBlockSize << endl;
	cout << "numBlocks: " << gNumBlocks << endl;
	cout << "suffixMax: " << gSuffixMax << endl;

	pre_sha256();

	uint64_t nonceOffset = 0;
	int shareDiff = 0;
	uint64_t nonceSolutionVal = 0;
	bool found = false;

	while (!gWorkData.HasNewWork())
	{
        usleep(100000);
	}
	gWorkData.getCtx(localCtx);
	cudaMemcpy(d_ctx, localCtx, sizeof(SHA256_CTX), cudaMemcpyHostToDevice);
	int foundInit = 0;
	cudaMemcpy(g_found, &foundInit, 4, cudaMemcpyHostToDevice);
	gWorkData.clearNewWork();
	shareDiff = gWorkData.shareDifficulty;

	t1 = std::chrono::high_resolution_clock::now();
	t_last_updated = std::chrono::high_resolution_clock::now();
	t_last_work_fetch = std::chrono::high_resolution_clock::now();

	while (true) {

		sha256_kernel << < gNumBlocks, gBlockSize >> > (g_out, g_found, d_ctx, nonceOffset, shareDiff, gSuffixMax);

		cudaError_t err = cudaDeviceSynchronize();
		if (err != cudaSuccess) {
			std::cout << "Cuda Error: " << cudaGetErrorString(err) << std::endl;
			throw std::runtime_error("Device error");
		}

		cudaMemcpy(&found, g_found, 1, cudaMemcpyDeviceToHost);

		if (found) {
			unsigned char nonceSolution[23];
			mutexWorkData.lock();
			memcpy(nonceSolution, &gWorkData.nonce[0], 15);
			mutexWorkData.unlock();
			cudaMemcpy(&nonceSolutionVal, g_out, 8, cudaMemcpyDeviceToHost);
			memcpy(nonceSolution + 15, &nonceSolutionVal, 8);
			//print_hash(nonceSolution);

			std::async(std::launch::async, submitwork_thread, std::ref(nonceSolution));

			found = 0;
			cudaMemcpy(g_found, &found, 1, cudaMemcpyHostToDevice);
		}

		gTotalNonce += hashesPerKernel;
		nonceOffset += blocksPerKernel;

		if (gWorkData.HasNewWork())
		{
			mutexWorkData.lock();
			gWorkData.getCtx(localCtx);
			mutexWorkData.unlock();

			cudaMemcpy(d_ctx, localCtx, sizeof(SHA256_CTX), cudaMemcpyHostToDevice);
			gWorkData.clearNewWork();
			//nonceOffset = 0;
		}
		shareDiff = gWorkData.shareDifficulty;
		//print_state();

		std::chrono::high_resolution_clock::time_point t2 = std::chrono::high_resolution_clock::now();

		std::chrono::duration<double, std::milli> last_show_interval = t2 - t_last_updated;
		if (last_show_interval.count() > SHOW_INTERVAL_MS) {
			t_last_updated = std::chrono::high_resolution_clock::now();
			std::chrono::duration<double, std::milli> span = t2 - t1;
			float ratio = span.count() / 1000;
			//std::cout << std::fixed << static_cast<uint64_t>(gTotalNonce / ratio) << " h/s S:" << totalSharesFound << " S/H:" << ((totalSharesFound *3600) / ratio) << std::endl;
			std::cout << std::fixed << static_cast<uint64_t>(gTotalNonce / ratio) << " h/s " << endl;
		}
	}

	cudaFree(g_out);
	cudaFree(g_found);

	cudaFree(d_ctx);

	cudaDeviceReset();

	return 0;
}
