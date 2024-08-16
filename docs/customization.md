# Customization

## Declarative

There are some degrees of declative possibilites, most of which based on [hetzn3r-k3s][hk3s] already built in possbilities.

Check [../conf.sh](../conf.sh) for the main configuration file.


## Extending / Bending the Functions

Main value, if any, is to suggest a somewhat solid and transparent basis for your own needs - i.e. you'll have to adapt the bash source and provide new

- variables (in [conf.sh](../conf.sh))
- functions (anywhere, ususally in [pkg](../pkg/)

or to change existing ones' (defaults)

### LSP

Lsp in use is shellcheck. This provides, besides formatting and diagnostics, mainly `gd` (goto definition) and is considered a must have to jump around in the code:

[![asciicast](https://asciinema.org/a/ARf3g4YtwHeD1TC64WUhDyPSd.svg)](https://asciinema.org/a/ARf3g4YtwHeD1TC64WUhDyPSd)


### Import system

Always sourced are only these:

```bash
  …/gitops❯ cat main.sh| grep source                                  ✘!? 🅒 tools
source "./conf.sh"
source "./tools.sh"
```

How are the functions elsewhere found, when you call your wrapper with e.g. a function name, e.g. 


```bash
  …/gitops❯ tests/setup.sh -h dns                                     ✘!? 🅒 tools
Installs NATed k3s on Hetzner Cloud, using vitobotta/hetzner-k3s

⚙️ Config:
HK_DNS_CLUSTER=10.60.0.10
DNS_PROVIDER=digitalocean
DNS_API_TOKEN=dop...
DNS_TTL=60


󰊕 Module pkg/dns [dns]:
digitalocean_dns_add
digitalocean_dns_by_name
digitalocean_dns_list
digitalocean_dns_rm
digitalocean_dns_rm_by_name
dns_add


  …/gitops❯ tests/setup.sh digitalocean_dns_list 
✔️ Loading module pkg/dns.sh
{
  "id": 3313..,
  "name": "@",
  "data": "1800",
  "ttl": 1800
}
 ...
```

That works with a helper function `import`, which will find the module containing the function, then sources it. The entry function in main will do that for you, i.e. finds the pkg module, which contained `digitalocean_dns_list`, by calling `import digitalocean_dns_list`. 

If a function from another package is required, while executing a function, then it can 'manually' import it:

E.g.:

```bash
     test i="nginx" && ingr=render_ingress_nginx || ingr="render_ingress_$ingress"
    import "$ingr"
    "$ingr" "$@"
```

Now, in order to keep the LSP working even for such dynamic imports but also for `goto definition` support for functions in `tools` and variables in `conf` outside the of the main module, which imports them statically, we use this trick at the end of modules:

```bash
false && . ./tools.sh && . ./conf.sh && . ./pkg/ingress.sh || true
```

This is not executed at runtime but tells [shellcheck][sc] where to look for.

[sc]: https://www.shellcheck.net/

