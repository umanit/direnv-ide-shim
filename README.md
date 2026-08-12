# direnv-ide-shim

Binaires shim (`ide-php`, `ide-composer`, …) qui résolvent, à chaque appel, l'environnement `direnv`/Nix du projet dans lequel ils sont lancés, puis délèguent au vrai binaire correspondant.

## Pourquoi

Les projets qui propulsent PHP via un `devShell` Nix (ex. `use flake` dans un `.envrc`) exposent des binaires dont le chemin dans le `/nix/store` change à chaque rebuild (mise à jour de `flake.lock`, garbage collection…). Les IDE comme PhpStorm exigent un chemin d'interpréteur figé et ne le relisent pas dynamiquement : après chaque rebuild, l'interpréteur configuré casse et doit être repointé à la main.

Ce flake fournit un point d'indirection stable : un seul binaire, installé une fois au niveau machine, valable pour **tous** les projets Nix/direnv de la machine.

## Fonctionnement

`ide-<outil>` exécute `direnv exec "$PWD" <outil> "$@"`. `direnv` remonte lui-même l'arborescence des dossiers pour trouver le `.envrc` du projet courant — le shim n'a donc besoin de rien savoir de la configuration du projet dans lequel il est appelé. Le nom `ide-<outil>` (plutôt que `<outil>` directement) évite tout risque de collision/récursion avec le binaire réel exporté par le `devShell`.

Prérequis, par projet cible : `direnv allow` doit avoir été exécuté au moins une fois (comportement standard `direnv`, indépendant de ce shim).

## Installation

### Machine NixOS / home-manager

```nix
inputs.direnv-ide-shim.url = "github:umanit/direnv-ide-shim";
# ...
home.packages = [ inputs.direnv-ide-shim.packages.${pkgs.system}.default ];
```

### Machine avec Nix seul (sans NixOS), ex. Ubuntu

```bash
nix profile install "github:umanit/direnv-ide-shim"
```

Dans les deux cas, `ide-php` / `ide-composer` sont disponibles dans le profil utilisateur (ex. `~/.nix-profile/bin/ide-php`).

## Configuration PhpStorm (par projet, une seule fois)

- `Settings › PHP › CLI Interpreters` → chemin vers `~/.nix-profile/bin/ide-php`.
- `Settings › PHP › Composer › Executable` → `~/.nix-profile/bin/ide-composer` (si ce réglage référence lui aussi un chemin `/nix/store/...` brut).

## Ajouter un outil

Ajouter son nom à la liste `tools` dans `flake.nix` (ex. `"symfony"`), rebuild — `ide-symfony` apparaît automatiquement.
