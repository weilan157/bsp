# microduck A733 编译环境（Ubuntu 22.04）
#
#   docker build --network host -t microduck-a733 -f docker/Dockerfile .
#   docker run --rm --network host -v "$PWD":/work -w /work microduck-a733 \
#       ./bsp config PLATFORM=a733 && ./bsp setup && ./bsp kernel
#
# 镜像里已经把 ./bsp env 要装的依赖装好（内核/u-boot/rootfs 三套）。
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential bc bison flex \
        libssl-dev libelf-dev libncurses-dev libgnutls28-dev uuid-dev \
        device-tree-compiler u-boot-tools \
        git rsync curl wget ca-certificates patch zstd cpio kmod \
        python3 python3-setuptools swig \
        gcc-aarch64-linux-gnu g++-aarch64-linux-gnu binutils-aarch64-linux-gnu \
        e2fsprogs dosfstools mtools lz4 debootstrap qemu-user-static sudo \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /work

CMD ["/bin/bash"]
