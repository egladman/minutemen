# bootstrap-minecraft

Build/Provision minecraft servers with forge mod support in seconds. 

### Need to know
 
- Currently only supports `ubuntu` and its derivatives


### Quick and Dirty

> curl | bash is indefensible. Just because the transport is over HTTPS doesn't guarantee the content hasn't been maliciously modified on the server. It also doesn't guarantee that you won't receive a partial download that happens to stop at some inopportune time. 

```
curl https://raw.githubusercontent.com/egladman/bootstrap-minecraft/master/bootstrap.sh | bash
```


### The proper way

```
git clone git@github.com:egladman/bootstrap-minecraft.git
cd bootstrap-minecraft
./bootstrap.sh
```

*Modify the script to your heart's content...
 
