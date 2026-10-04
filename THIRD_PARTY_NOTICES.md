# 第三者の著作権とライセンス表示

Windows DLL は Microsoft.GameInput 3.5.283 の `native/src/GameInput.cpp` に対応する MIT ローダーを `GameInput.lib` から静的リンクします。SDK ヘッダーと Microsoft ランタイム MSI は同梱しません。別途インストールする Microsoft GameInput ランタイムには Microsoft の利用条件が適用されます。

ローダーの原文表示を以下に保持します。

Bluetooth の vendor UUID と報告の field は [SDL fork の一次実装・文書](https://github.com/hifihedgehog/SDL/blob/feat/hidmaestro-filter/docs/README-xinput-paddles.md) を調査して仕様の根拠を引用しました。配布 GATT module は独自実装であり、この fork のサービスメモリ構造、非公開 offset、USB enable コードは含みません。参考 fork のコードライセンスは zlib で、Microsoft ローダー/runtime の条件とは別です。

```text
Copyright (c) Microsoft Corporation.

This file is licensed under the MIT License.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
