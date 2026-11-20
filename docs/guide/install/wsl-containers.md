# Running Lemonade in WSL Containers

[WSL containers](https://learn.microsoft.com/windows/wsl/wsl-container) run the [Lemonade container image](./docker.md) on Windows without Docker. Their `wslc` CLI is part of WSL 2.9.3 and later, so run `wsl --update` to get it, then run the commands below in PowerShell.

`wslc` publishes `-p 13305:13305` on `127.0.0.1` only, so the server is reachable from this machine and not from the network. A container session gets half of the machine's memory by default. [WSL container settings](https://learn.microsoft.com/windows/wsl/wsl-container-settings) change both.

## Run with Default Configuration

```powershell
wslc run -d `
  --name lemonade-server `
  -p 13305:13305 `
  -v lemonade-cache:/opt/lemonade/.cache/huggingface `
  -v lemonade-llama:/opt/lemonade/llama `
  -v lemonade-data:/opt/lemonade/.cache/lemonade `
  -v lemonade-config:/opt/lemonade/.config/lemonade `
  ghcr.io/lemonade-sdk/lemonade-server:latest
```

Once the container is running, verify it's working:

```powershell
curl.exe http://localhost:13305/api/v1/models
```

## Run with AMD GPU Passthrough using ROCm

Install the Windows driver that [ROCm for WSL](https://rocm.docs.amd.com/projects/radeon-ryzen/en/latest/docs/install/installrad/wsl/howto_wsl.html) lists. ROCm itself does not have to be installed in a WSL distribution: `--gpus all` gives the container `/dev/dxg` and WSL's GPU libraries, and Lemonade downloads its own ROCm runtime.

```powershell
wslc run -d `
  --name lemonade-server `
  --gpus all `
  -p 13305:13305 `
  -v lemonade-cache:/opt/lemonade/.cache/huggingface `
  -v lemonade-llama:/opt/lemonade/llama `
  -v lemonade-data:/opt/lemonade/.cache/lemonade `
  -v lemonade-config:/opt/lemonade/.config/lemonade `
  ghcr.io/lemonade-sdk/lemonade-server:latest
```

Then make ROCm the default backend for llama.cpp:

```powershell
wslc exec lemonade-server lemonade config set llamacpp.backend=rocm
```

> Note: The first model load downloads the ROCm runtime, several gigabytes, into the `lemonade-data` volume.
