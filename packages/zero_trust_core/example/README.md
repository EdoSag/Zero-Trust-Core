# Platform smoke check

A tiny app that opens the shared encrypted store (`ZtLocalStore`) and reports
whether it works: write, close, reopen, read back, refuse a wrong key. It
exists so CI catches anything that stops Zero-Trust Core building for the web
or desktop.

```sh
../../../tool/fetch_sqlite3mc_wasm.sh web/   # once, for the web build
flutter run -d chrome --no-web-resources-cdn
flutter run -d linux
```

The result is printed and shown on screen, starting with `PASS` or `FAIL`.
