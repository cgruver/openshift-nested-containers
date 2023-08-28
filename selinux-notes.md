# SeLinux Notes

```bash
audit2allow -a -M setest
```

```bash
ausearch -m AVC -ts recent
```

```bash
checkmodule -M -m -o setest.mod setest.te && semodule_package -o setest.pp -m setest.mod && semodule -i setest.pp
```
