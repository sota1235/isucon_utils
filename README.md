# ISUCON utils 

Just for me.

# How to set up

## For infrastructure player

1. Setting up ssh
    - Rewrite `setting_up_ssh` command on Makefile
2. Run `make setting_up_ssh` command
3. Run `make bootstrap` command

## For other players

After setting up by infrastructure player, test it.

1. Copy [tools/ssh/config_local](tools/ssh/config_local) to local ssh config file and rewrite TODO statements.
2. Test `ssh ${target}` command

# How to use

## Makefile usage

If you want to use commands for specific ssh client, you can use `SSH_NAME`.

```shell
make bootstrap SSH_NAME=isucon11-2
```

You can specify git branch name by use `GIT_BRANCH`

```shell
make bootstrap GIT_BRANCH=feature-nplus1
```
