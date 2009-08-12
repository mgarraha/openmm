/* -------------------------------------------------------------------------- *
 *                                   OpenMM                                   *
 * -------------------------------------------------------------------------- *
 * This is part of the OpenMM molecular simulation toolkit originating from   *
 * Simbios, the NIH National Center for Physics-Based Simulation of           *
 * Biological Structures at Stanford, funded under the NIH Roadmap for        *
 * Medical Research, grant U54 GM072970. See https://simtk.org.               *
 *                                                                            *
 * Portions copyright (c) 2009 Stanford University and the Authors.           *
 * Authors: Scott Le Grand, Peter Eastman                                     *
 * Contributors:                                                              *
 *                                                                            *
 * This program is free software: you can redistribute it and/or modify       *
 * it under the terms of the GNU Lesser General Public License as published   *
 * by the Free Software Foundation, either version 3 of the License, or       *
 * (at your option) any later version.                                        *
 *                                                                            *
 * This program is distributed in the hope that it will be useful,            *
 * but WITHOUT ANY WARRANTY; without even the implied warranty of             *
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the              *
 * GNU Lesser General Public License for more details.                        *
 *                                                                            *
 * You should have received a copy of the GNU Lesser General Public License   *
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.      *
 * -------------------------------------------------------------------------- */

#include <stdio.h>
#include <cuda.h>
#include <vector_functions.h>
#include <cstdlib>
#include <string>
#include <iostream>
#include <fstream>
using namespace std;

#include "gputypes.h"
#include "cudatypes.h"

#define UNROLLXX 0
#define UNROLLXY 0

struct Atom {
    float x;
    float y;
    float z;
    float4 params;
    float fx;
    float fy;
    float fz;
};

static __constant__ cudaGmxSimulation cSim;
static __constant__ Expression<128> forceExp;
static __constant__ Expression<128> energyExp;
static __constant__ Expression<64> combiningRules[4];
static __constant__ float globalParams[8];

void SetCalculateCustomNonbondedForcesSim(gpuContext gpu)
{
    cudaError_t status;
    status = cudaMemcpyToSymbol(cSim, &gpu->sim, sizeof(cudaGmxSimulation));
    RTERROR(status, "cudaMemcpyToSymbol: SetSim copy to cSim failed");
}

void GetCalculateCustomNonbondedForcesSim(gpuContext gpu)
{
    cudaError_t status;
    status = cudaMemcpyFromSymbol(&gpu->sim, cSim, sizeof(cudaGmxSimulation));
    RTERROR(status, "cudaMemcpyFromSymbol: SetSim copy from cSim failed");
}

void SetCustomNonbondedForceExpression(const Expression<128>& expression)
{
    cudaError_t status;
    status = cudaMemcpyToSymbol(forceExp, &expression, sizeof(forceExp));
    RTERROR(status, "SetCustomNonbondedForceExpression: cudaMemcpyToSymbol failed");
}

void SetCustomNonbondedEnergyExpression(const Expression<128>& expression)
{
    cudaError_t status;
    status = cudaMemcpyToSymbol(energyExp, &expression, sizeof(energyExp));
    RTERROR(status, "SetCustomNonbondedEnergyExpression: cudaMemcpyToSymbol failed");
}

void SetCustomNonbondedCombiningRules(const Expression<64>* expressions)
{
    cudaError_t status;
    status = cudaMemcpyToSymbol(combiningRules, expressions, sizeof(combiningRules));
    RTERROR(status, "SetCustomNonbondedCombiningRules: cudaMemcpyToSymbol failed");
}

void SetCustomNonbondedGlobalParams(const vector<float>& paramValues)
{
    cudaError_t status;
    status = cudaMemcpyToSymbol(globalParams, &paramValues[0], sizeof(globalParams));
    RTERROR(status, "SetCustomNonbondedGlobalParams: cudaMemcpyToSymbol failed");
}

#define STACK(y) stack[(y)*blockDim.x+threadIdx.x]

template<int SIZE>
__device__ float kEvaluateExpression_kernel(Expression<SIZE>* expression, float* stack, float var0, float4 vars1, float4 vars2)
{
    int stackPointer = -1;
    for (int i = 0; i < expression->length; i++)
    {
        switch (expression->op[i])
        {
            case CONSTANT:
                STACK(++stackPointer) = expression->arg[i];
                break;
            case VARIABLE0:
                STACK(++stackPointer) = var0;
                break;
            case VARIABLE1:
                STACK(++stackPointer) = vars1.x;
                break;
            case VARIABLE2:
                STACK(++stackPointer) = vars1.y;
                break;
            case VARIABLE3:
                STACK(++stackPointer) = vars1.z;
                break;
            case VARIABLE4:
                STACK(++stackPointer) = vars1.w;
                break;
            case VARIABLE5:
                STACK(++stackPointer) = vars2.x;
                break;
            case VARIABLE6:
                STACK(++stackPointer) = vars2.y;
                break;
            case VARIABLE7:
                STACK(++stackPointer) = vars2.z;
                break;
            case VARIABLE8:
                STACK(++stackPointer) = vars2.w;
                break;
            case GLOBAL:
                STACK(++stackPointer) = globalParams[(int) expression->arg[i]];
                break;
            case ADD:
            {
                float temp = STACK(stackPointer);
                STACK(--stackPointer) += temp;
                break;
            }
            case SUBTRACT:
            {
                float temp = STACK(stackPointer);
                STACK(stackPointer) = temp-STACK(--stackPointer);
                break;
            }
            case MULTIPLY:
            {
                float temp = STACK(stackPointer);
                STACK(--stackPointer) *= temp;
                break;
            }
            case DIVIDE:
            {
                float temp = STACK(stackPointer);
                STACK(stackPointer) = temp/STACK(--stackPointer);
                break;
            }
            case POWER:
            {
                float temp = STACK(stackPointer);
                STACK(stackPointer) = pow(temp, STACK(--stackPointer));
                break;
            }
            case NEGATE:
                STACK(stackPointer) *= -1.0f;
                break;
            case SQRT:
                STACK(stackPointer) = sqrt(STACK(stackPointer));
                break;
            case EXP:
                STACK(stackPointer) = exp(STACK(stackPointer));
                break;
            case LOG:
                STACK(stackPointer) = log(STACK(stackPointer));
                break;
            case SIN:
                STACK(stackPointer) = sin(STACK(stackPointer));
                break;
            case COS:
                STACK(stackPointer) = cos(STACK(stackPointer));
                break;
            case SEC:
                STACK(stackPointer) = 1.0f/cos(STACK(stackPointer));
                break;
            case CSC:
                STACK(stackPointer) = 1.0f/sin(STACK(stackPointer));
                break;
            case TAN:
                STACK(stackPointer) = tan(STACK(stackPointer));
                break;
            case COT:
                STACK(stackPointer) = 1.0f/tan(STACK(stackPointer));
                break;
            case ASIN:
                STACK(stackPointer) = asin(STACK(stackPointer));
                break;
            case ACOS:
                STACK(stackPointer) = acos(STACK(stackPointer));
                break;
            case ATAN:
                STACK(stackPointer) = atan(STACK(stackPointer));
                break;
            case SQUARE:
            {
                float temp = STACK(stackPointer);
                STACK(stackPointer) *= temp;
                break;
            }
            case CUBE:
            {
                float temp = STACK(stackPointer);
                STACK(stackPointer) *= temp*temp;
                break;
            }
            case RECIPROCAL:
                STACK(stackPointer) = 1.0f/STACK(stackPointer);
                break;
            case INCREMENT:
                STACK(stackPointer) += 1.0f;
                break;
            case DECREMENT:
                STACK(stackPointer) -= 1.0f;
                break;
        }
    }
    return STACK(stackPointer);
}

// Include versions of the kernels for N^2 calculations.

#define METHOD_NAME(a, b) a##N2##b
#include "kCalculateCustomNonbondedForces.h"
#define USE_OUTPUT_BUFFER_PER_WARP
#undef METHOD_NAME
#define METHOD_NAME(a, b) a##N2ByWarp##b
#include "kCalculateCustomNonbondedForces.h"

// Include versions of the kernels with cutoffs.

#undef METHOD_NAME
#undef USE_OUTPUT_BUFFER_PER_WARP
#define USE_CUTOFF
#define METHOD_NAME(a, b) a##Cutoff##b
#include "kCalculateCustomNonbondedForces.h"
#define USE_OUTPUT_BUFFER_PER_WARP
#undef METHOD_NAME
#define METHOD_NAME(a, b) a##CutoffByWarp##b
#include "kCalculateCustomNonbondedForces.h"

// Include versions of the kernels with periodic boundary conditions.

#undef METHOD_NAME
#undef USE_OUTPUT_BUFFER_PER_WARP
#define USE_PERIODIC
#define METHOD_NAME(a, b) a##Periodic##b
#include "kCalculateCustomNonbondedForces.h"
#define USE_OUTPUT_BUFFER_PER_WARP
#undef METHOD_NAME
#define METHOD_NAME(a, b) a##PeriodicByWarp##b
#include "kCalculateCustomNonbondedForces.h"

__global__ void kFindBlockBoundsCutoff_kernel();
__global__ void kFindBlocksWithInteractionsCutoff_kernel();
__global__ void kFindInteractionsWithinBlocksCutoff_kernel(unsigned int* workUnit);
__global__ void kFindBlockBoundsPeriodic_kernel();
__global__ void kFindBlocksWithInteractionsPeriodic_kernel();
__global__ void kFindInteractionsWithinBlocksPeriodic_kernel(unsigned int* workUnit);

void kCalculateCustomNonbondedForces(gpuContext gpu, bool neighborListValid)
{
//    printf("kCalculateCustomNonbondedCutoffForces\n");
    CUDPPResult result;
    int sharedPerThread = sizeof(Atom)+gpu->sim.customExpressionStackSize*sizeof(float);
    if (gpu->sim.customNonbondedMethod != NO_CUTOFF)
        sharedPerThread += sizeof(float3);
    int threads = gpu->sim.nonbond_threads_per_block;
    int maxThreads = 16380/sharedPerThread;
    if (threads > maxThreads)
        threads = (maxThreads/32)*32;
    switch (gpu->sim.customNonbondedMethod)
    {
        case NO_CUTOFF:
            if (gpu->bOutputBufferPerWarp)
                kCalculateCustomNonbondedN2ByWarpForces_kernel<<<gpu->sim.nonbond_blocks, threads, sharedPerThread*threads>>>(gpu->sim.pWorkUnit);
            else
                kCalculateCustomNonbondedN2Forces_kernel<<<gpu->sim.nonbond_blocks, threads, sharedPerThread*threads>>>(gpu->sim.pWorkUnit);
            LAUNCHERROR("kCalculateCustomNonbondedN2Forces");
            kCalculateCustomNonbondedN2Exceptions_kernel<<<gpu->sim.blocks, gpu->sim.custom_exception_threads_per_block,
                    gpu->sim.customExpressionStackSize*sizeof(float)*gpu->sim.custom_exception_threads_per_block>>>();
            LAUNCHERROR("kCalculateCustomNonbondedN2Exceptions");
            break;
        case CUTOFF:
            if (!neighborListValid)
            {
                kFindBlockBoundsCutoff_kernel<<<(gpu->psGridBoundingBox->_length+63)/64, 64>>>();
                LAUNCHERROR("kFindBlockBoundsCutoff");
                kFindBlocksWithInteractionsCutoff_kernel<<<gpu->sim.interaction_blocks, gpu->sim.interaction_threads_per_block>>>();
                LAUNCHERROR("kFindBlocksWithInteractionsCutoff");
                result = cudppCompact(gpu->cudpp, gpu->sim.pInteractingWorkUnit, gpu->sim.pInteractionCount,
                        gpu->sim.pWorkUnit, gpu->sim.pInteractionFlag, gpu->sim.workUnits);
                if (result != CUDPP_SUCCESS)
                {
                    printf("Error in cudppCompact: %d\n", result);
                    exit(-1);
                }
                kFindInteractionsWithinBlocksCutoff_kernel<<<gpu->sim.nonbond_blocks, gpu->sim.nonbond_threads_per_block,
                        sizeof(unsigned int)*gpu->sim.nonbond_threads_per_block>>>(gpu->sim.pInteractingWorkUnit);
            }
            if (gpu->bOutputBufferPerWarp)
                kCalculateCustomNonbondedCutoffByWarpForces_kernel<<<gpu->sim.nonbond_blocks, threads, sharedPerThread*threads>>>(gpu->sim.pInteractingWorkUnit);
            else
                kCalculateCustomNonbondedCutoffForces_kernel<<<gpu->sim.nonbond_blocks, threads, sharedPerThread*threads>>>(gpu->sim.pInteractingWorkUnit);
            LAUNCHERROR("kCalculateCustomNonbondedCutoffForces");
            kCalculateCustomNonbondedCutoffExceptions_kernel<<<gpu->sim.blocks, gpu->sim.custom_exception_threads_per_block,
                    gpu->sim.customExpressionStackSize*sizeof(float)*gpu->sim.custom_exception_threads_per_block>>>();
            LAUNCHERROR("kCalculateCustomNonbondedCutoffExceptions");
            break;
        case PERIODIC:
            if (!neighborListValid)
            {
                kFindBlockBoundsPeriodic_kernel<<<(gpu->psGridBoundingBox->_length+63)/64, 64>>>();
                LAUNCHERROR("kFindBlockBoundsPeriodic");
                kFindBlocksWithInteractionsPeriodic_kernel<<<gpu->sim.interaction_blocks, gpu->sim.interaction_threads_per_block>>>();
                LAUNCHERROR("kFindBlocksWithInteractionsPeriodic");
                result = cudppCompact(gpu->cudpp, gpu->sim.pInteractingWorkUnit, gpu->sim.pInteractionCount,
                        gpu->sim.pWorkUnit, gpu->sim.pInteractionFlag, gpu->sim.workUnits);
                if (result != CUDPP_SUCCESS)
                {
                    printf("Error in cudppCompact: %d\n", result);
                    exit(-1);
                }
                kFindInteractionsWithinBlocksPeriodic_kernel<<<gpu->sim.nonbond_blocks, gpu->sim.nonbond_threads_per_block,
                        sizeof(unsigned int)*gpu->sim.nonbond_threads_per_block>>>(gpu->sim.pInteractingWorkUnit);
            }
            if (gpu->bOutputBufferPerWarp)
                kCalculateCustomNonbondedPeriodicByWarpForces_kernel<<<gpu->sim.nonbond_blocks, threads, sharedPerThread*threads>>>(gpu->sim.pInteractingWorkUnit);
            else
                kCalculateCustomNonbondedPeriodicForces_kernel<<<gpu->sim.nonbond_blocks, threads, sharedPerThread*threads>>>(gpu->sim.pInteractingWorkUnit);
            LAUNCHERROR("kCalculateCustomNonbondedPeriodicForces");
            kCalculateCustomNonbondedPeriodicExceptions_kernel<<<gpu->sim.blocks, gpu->sim.custom_exception_threads_per_block,
                    gpu->sim.customExpressionStackSize*sizeof(float)*gpu->sim.custom_exception_threads_per_block>>>();
            LAUNCHERROR("kCalculateCustomNonbondedPeriodicExceptions");
            break;
    }
}