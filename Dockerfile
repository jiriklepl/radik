# NVIDIA GPU SM version (Compute Capability)
ARG SM_VERSION=75

# ===========================
# Build image
FROM nvidia/cuda:12.6.0-devel-ubuntu20.04 AS build-image
ARG SM_VERSION

RUN apt-get update && apt-get install -y wget patch openssl libssl-dev build-essential

WORKDIR /root/building

# Install CMake
RUN wget https://github.com/Kitware/CMake/releases/download/v3.26.3/cmake-3.26.3.tar.gz
RUN tar xzf cmake-3.26.3.tar.gz
RUN cd cmake-3.26.3 && ./configure --parallel=`nproc` && make -j`nproc` && make install

# Clean up
RUN rm -rf /root/building

ENV CUDA_SM_VERSION ${SM_VERSION}
ENV CUDA_HOME /usr/local/cuda

WORKDIR /radik

# Build bitonic select
COPY bitonic bitonic
COPY patches/bitonic/Makefile.patch bitonic
RUN cd bitonic && patch Makefile Makefile.patch
RUN cd bitonic && make -j`nproc` CUDA_PATH=$CUDA_HOME GENCODE_FLAGS=-arch=sm_$CUDA_SM_VERSION

# Build block select (PQ-block)
COPY blockselect blockselect
RUN cd blockselect && make -j`nproc` all && make clean

# Build RadiK & grid select (PQ-grid)
COPY radik radik
RUN cd radik && make -j`nproc` all

# ===========================
# Release image
FROM nvidia/cuda:12.6.0-runtime-ubuntu20.04

RUN apt-get update && apt-get install -y python3 python3-pip

# Copy built binaries
COPY --from=build-image /radik /radik
WORKDIR /radik

# Install Python requirements
RUN python3 -m pip install pip -U
COPY requirements.txt .
RUN python3 -m pip install -r requirements.txt

# Evaluation scripts
COPY eval eval

COPY scripts/entry.sh /opt
RUN chmod +x /opt/entry.sh
ENTRYPOINT ["/opt/entry.sh"]
