#Requires AutoHotkey v1.1.35+
;==============================================================
; HttpRequestManager — WinHTTP-based sync/async HTTP helper with timeouts & URI utilities
;
; GitHub: https://github.com/SevenKeyboard/http-request-manager
; Author: SevenKeyboard Ltd. (2025)
; License: MIT License
;==============================================================
class VersionManager_HttpRequestManager
{
    static _ := VersionManager_HttpRequestManager._init()
    _init()    {
        global
        HTTPREQUESTMANAGER_VERSION := "1.0.0"
    }
}
class HttpRequestManager
{
    get(url, callback, timeout)    {
        i := this._acquireRequestIndex() ;  outputDebug % "Request Index : " i
        switch
        {
            default:            return (i ? this._sendHttpGetSync(i, "GET", url, "", "") : "")
            case (callback):    return (i ? this._sendHttpGetAsync(i, "GET", url, "", "", callback, timeout) : false)
        }
    }
    post(url, contentType, body, callback, timeout)    {
        i := this._acquireRequestIndex() ;  outputDebug % "Request Index : " i
        switch
        {
            default:            return (i ? this._sendHttpGetSync(i, "POST", url, contentType, body) : "")
            case (callback):    return (i ? this._sendHttpGetAsync(i, "POST", url, contentType, body, callback, timeout) : false)
        }
    }
    ;-----------------------------------------------
    static _refererUrl := "https://www.bing.com/"
    RefererUrl    {
        get  {
            return this._refererUrl
        }
        set  {
            this._refererUrl := value
            return this._refererUrl
        }
    }
    _sendHttpGetSync(reqIndex, method, url, contentType, body)    {
        this._setRequestRunning(reqIndex, true)
        try  {
            req := this._reqList[reqIndex]
            req.open(method, url, false)
            req.setRequestHeader("User-Agent", this._getRandomUserAgent())
            if (contentType !== "")
                req.setRequestHeader("Content-Type", contentType)
            req.setRequestHeader("Cache-Control", "no-cache")
            req.setRequestHeader("Pragma", "no-cache")
            if (this.RefererUrl !== "")
                req.setRequestHeader("Referer", this.RefererUrl)
            req.setTimeouts(2000, 3000, 2000, 6000)
            req.send(body)
            responseText := req.ResponseText
        }  catch  {
            responseText := ""
        }
        this._setRequestRunning(reqIndex, false)
        return responseText
    }
    _sendHttpGetAsync(reqIndex, method, url, contentType, body, callback, timeout)    {
        this._setRequestRunning(reqIndex, true)
        this._setAsyncMeta(reqIndex, callback, timeout, this._TickCount)
        try  {
            req := this._reqList[reqIndex]
            req.open(method, url, true)
            req.setRequestHeader("User-Agent", this._getRandomUserAgent())
            if (contentType !== "")
                req.setRequestHeader("Content-Type", contentType)
            req.setRequestHeader("Cache-Control", "no-cache")
            req.setRequestHeader("Pragma", "no-cache")
            if (this.RefererUrl !== "")
                req.setRequestHeader("Referer", this.RefererUrl)
            if (timeout)    {
                req.setTimeouts(max(2000, timeout + 1000)
                    ,max(3000, timeout + 1000)
                    ,max(2000, timeout + 1000)
                    ,max(6000, timeout + 1000))
            }  else  {
                req.setTimeouts(0, 0, 0, 0)
            }
            req.send(body)
            b := true
        }  catch  {
            b := false
        }
        if (b)    {
            fn := this._getRequestMetaValue(reqIndex, "asyncTimerId")
            setTimer % fn, 100
        }  else  {
            this._resetAsyncMeta(reqIndex)
            this._setRequestRunning(reqIndex, false)
        }
        return b
    }
    _checkAsyncResult(reqIndex)    {
        static VARIANT_TRUE := -1
            ,VARIANT_FALSE := 0
        critical % format("{2}", prevIC := A_IsCritical, "On")
        req := this._reqList[reqIndex]
        succeeded := req.waitForResponse(0)
        switch (succeeded)
        {
            case VARIANT_FALSE: ;  Either waiting for a response or already timed out.
                timeout := this._getRequestMetaValue(reqIndex, "asyncTimeout")
                if (timeout)    {
                    currTick := this._TickCount
                    startTick := this._getRequestMetaValue(reqIndex, "asyncStartTick")
                    isWaiting := (startTick <= currTick && currTick - startTick <= timeout)
                    if (!isWaiting)    {
                        /*
                        Intentionally leave the request slot as a dummy after timeout,
                        since the response may still arrive later and we cannot fully determine its state.
                        */
                        fn := this._getRequestMetaValue(reqIndex, "asyncTimerId")
                        setTimer % fn, % "Delete"
                        callback := this._getRequestMetaValue(reqIndex, "asyncCallback")
                        callback.call(false)
                        this._resetAsyncMeta(reqIndex) ;  Leave callback empty to ignore response text.
                    }
                }
            case VARIANT_TRUE:
                fn := this._getRequestMetaValue(reqIndex, "asyncTimerId")
                setTimer % fn, % "Delete"
                callback := this._getRequestMetaValue(reqIndex, "asyncCallback")
                if (callback)
                    callback.call(true, req.ResponseText)
                this._resetAsyncMeta(reqIndex)
                this._setRequestRunning(reqIndex, false)
        }
        critical % prevIC
    }
    ;-----------------------------------------------
    static _reqList := [], _reqMeta := []
    _acquireRequestIndex()    {
        reqIndex := 0
        for i, meta in this._reqMeta    {
            if (!meta.running)    {
                reqIndex := i
                break
            }
        }
        if (!reqIndex)    {
            this._reqList.push(comObjCreate("WinHTTP.WinHTTPRequest.5.1"))
            reqIndex := this._reqList.length()
            if (isObject(this._reqList[reqIndex]))    {
                this._reqMeta.push({running:false
                    ,asyncTimerId:objBindMethod(this, "_checkAsyncResult", reqIndex)
                    ,asyncCallback:""
                    ,asyncStartTick:0
                    ,asyncTimeout:0})
            }  else  {
                this._reqList.pop()
                reqIndex := 0
            }
        }
        return reqIndex
    }
    _setRequestRunning(reqIndex, b)    {
        this._reqMeta[reqIndex].running := b
    }
    _getRequestMetaValue(reqIndex, key)    {
        return this._reqMeta[reqIndex][key]
    }
    _setAsyncMeta(reqIndex, callback, timeout, startTick)    {
        this._reqMeta[reqIndex].asyncCallback := callback
        this._reqMeta[reqIndex].asyncTimeout := timeout
        this._reqMeta[reqIndex].asyncStartTick := startTick
    }
    _resetAsyncMeta(reqIndex)    {
        this._setAsyncMeta(reqIndex, "", 0, 0)
    }
    ;-----------------------------------------------
    uriDecode(uri, enc := "UTF-8")    {
        pos := 1
        loop
        {
            pos := regExMatch(uri, "i)(?:%[\da-f]{2})+", code, pos++)
            if (pos == 0)
                break
            varSetCapacity(var, strLen(code) // 3, 0)
            code := subStr(code, 2) ;  StringTrimLeft, Code, Code, 1
            loop Parse, % code, % "%"
                numPut("0x" . A_LoopField, var, A_Index - 1, "UChar")
            uri := strReplace(uri, "%" code, strGet(&var, Enc)) ;  StringReplace, Uri, Uri, `%%Code%, % StrGet(&Var, Enc), All
        }
        return uri
    }
    uriEncode(uri, enc = "UTF-8")    {
        this._strPutVar(uri, var, enc)
        loop    {
            code := numGet(var, A_Index - 1, "UChar")
            if (!code)
                break
            if (0x30 <= code && code <= 0x39) ;  0-9
            || (0x41 <= code && code <= 0x5A) ;  A-Z
            || (0x61 <= code && code <= 0x7A) ;  a-z
                res .= chr(code)
            else
                res .= "%" . subStr(format("{:02X}", code), -1)
        }
        return res
    }
    _strPutVar(str, byRef var, enc := "")    {
        len := strPut(str, enc) * (enc = "UTF-16" || enc = "CP1200" ? 2 : 1)
        varSetCapacity(var, len, 0)
        return strPut(str, &var, enc)
    }
    _getRandomUserAgent()    {
        static userAgent
        if (!isSet(userAgent))    {
            random chromeVer, 101, 140
            userAgent := "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/" . chromeVer . "0.0.0 Safari/537.36"
        }
        return userAgent
    }
    _TickCount    {
        get  {
            return A_Is64bitOS
                ? dllCall("Kernel32.dll\GetTickCount64", "Int64") & 0x7FFFFFFFFFFFFFFF ;  0x0 to 0x7FFFFFFFFFFFFFFF
                : dllCall("Kernel32.dll\GetTickCount", "UInt") ;  0x0 to 0xFFFFFFFF
        }
    }
}