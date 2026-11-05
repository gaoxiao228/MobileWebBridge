# DSBridge third-party notice

DSBridge JavaScript 3.1.4: https://www.npmjs.com/package/dsbridge/v/3.1.4
DSBridge Android 3.0.0: https://github.com/wendux/DSBridge-Android/tree/d3e5ebc6ca8170f97e420f2f482680c8e149b471
DSBridge iOS 3.0.6: https://github.com/wendux/DSBridge-IOS/tree/f0e3c724dd362800528f8b6c788bdad7006cc187

Author: wendux (杜文 / Du Wen), as identified by upstream package metadata and source.
The upstream npm metadata, Android readme.md and iOS podspec declare MIT.
The pinned native trees do not provide a separate LICENSE file; the MIT terms
are reproduced below without inventing an absent upstream copyright notice.
Original iOS source notices are retained verbatim:

Copyright © 2016年 杜文. All rights reserved.
Copyright © 2018年 杜文. All rights reserved.

MIT License

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

## Local integration

The fixed iOS vendor code is integrated with a Swift container and current Xcode.
MWB-specific prompt, callback and event guards are implemented in MWB Sources.
When upgrading DSBridge, verify both the bridge registration and dscbN callback contract.
