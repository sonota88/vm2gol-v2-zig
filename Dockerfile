FROM ubuntu:24.04

RUN apt update \
  && apt install -y --no-install-recommends \
    ca-certificates \
    ruby \
    wget \
    xz-utils \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

ARG USER
ARG GROUP

# https://askubuntu.com/questions/1513927/ubuntu-24-04-docker-images-now-includes-user-ubuntu-with-uid-gid-1000
RUN userdel -r ubuntu

RUN groupadd ${USER} \
  && useradd ${USER} -g ${GROUP} -m

USER ${USER}

WORKDIR /home/${USER}

ARG version="0.11.0"
ARG archive_file="zig-linux-x86_64-${version}.tar.xz"

RUN wget -q \
    "https://ziglang.org/download/${version}/${archive_file}" \
  && tar xf "$archive_file" \
  && mv "zig-linux-x86_64-${version}/" "zig/" \
  && rm "$archive_file"

ENV PATH="/home/${USER}/zig:${PATH}"

RUN mkdir /home/${USER}/work

WORKDIR /home/${USER}/work

ENV IN_CONTAINER=1
