# bootstrap

sample usage without extra options
```sh
curl https://raw.githubusercontent.com/mfld/dotfiles/refs/heads/main/bootstrap/install_fedora.sh | sh
```
sample usage to setup autofs and synology drive service
```sh
curl https://raw.githubusercontent.com/mfld/dotfiles/refs/heads/main/bootstrap/install_fedora.sh | SYNDRIVE=1 AUTOFS="server.example:/volume" sh
```
**NOTE:** Remember you local UID should correspond to that on Synology (NFS).