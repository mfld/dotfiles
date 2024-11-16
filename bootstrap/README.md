# bootstrap

sample usage without extra options.
```sh
curl https://raw.githubusercontent.com/mfld/dotfiles/refs/heads/main/bootstrap/install_fedora.sh | sh
```

WITH AUTOFS
```sh
curl https://raw.githubusercontent.com/mfld/dotfiles/refs/heads/main/bootstrap/install_fedora.sh | AUTOFS="server.example:/volume" sh
```
NFS-shares are then available under `/n/<path>`.

**NOTE:** Ensure your local UID corresponds to that of Synology (NFS).

WITH SYNOLOGY DRIVE
sample usage to setup autofs and synology drive service.
```sh
curl https://raw.githubusercontent.com/mfld/dotfiles/refs/heads/main/bootstrap/install_fedora.sh | AUTOFS="server.example:/volume" SYNDRIVE=1 sh
```
`SYNDRIVE=1` or `SYNDRIVE=true` is used to install synology drive and start the service at login.

After setup, create symlinks to the Synology Drive folder for sensitive files.

Sample on fresh install.
```sh
cd # go to home directory
mv Documents drive/
mv .bashrc drive/bashrc
mv .bash_history drive/bash_history

ln -s drive/Documents Documents
ln -s drive/bashrc .bashrc
ln -s drive/bash_history .bash_history
```

Sample when Synology drive already holds your files and folders.
```sh
cd # go to home directory
rmdir Documents
rmdir .ssh
rm bashrc bash_history

ln -s drive/documents documents
ln -s drive/bashrc .bashrc
ln -s drive/bash_history .bash_history
ln -s drive/ssh .ssh
```
