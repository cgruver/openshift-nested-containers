# SeLinux Notes

## Create a profile based on audit logs

```bash
audit2allow -a -M setest
```

## Enable more verbose logging of events

```bash
semodule -DB
```

## Undo verbose logging

```bash
semodule -B
```

## Display recent denial events

```bash
ausearch -m AVC -ts recent
```

## Apply profile changes

```bash
checkmodule -M -m -o setest.mod setest.te && semodule_package -o setest.pp -m setest.mod && semodule -i setest.pp
```
