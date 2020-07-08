# sh.moul.io

[![Netlify Status](https://api.netlify.com/api/v1/badges/25622023-5703-42ff-9b10-3d7ad75db31a/deploy-status)](https://app.netlify.com/sites/sh-moul-io/deploys)

Common commands I run when I arrive on a new server :)

## Usage

```command
# download and execute the script without argument (display help)
$> curl -s https://sh.moul.io | sh
Usage: sh <subcommand> [options]

Subcommands:
    authorized_keys     add keys from github.com/moul.keys into .ssh/authorized_keys
    [...]

More info: https://github.com/moul/sh.moul.io
```

```command
# run authorized_keys subcommand
$> curl -s https://sh.moul.io | sh -s -- authorized_keys
```

## Alternative usages

```command
# download the script
curl -s https://sh.moul.io > sh-moul-io.sh
# execute without argument
sh sh-moul-io.sh
# execute with arguments
sh sh-moul.io.sh authorized_keys
```
