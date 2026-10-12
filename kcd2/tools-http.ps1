#requires -Version 7.0
# SPDX-License-Identifier: GPL-3.0-or-later
# Direct, bounded HTTP for the official tools' numeric loopback endpoint only.
function Invoke-MineComeToolsRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$PathAndQuery,
        [ValidateRange(1,65535)][int]$Port = 1403,
        [ValidateRange(1,30000)][int]$TimeoutMilliseconds = 3000,
        [ValidateRange(1,1048576)][int]$MaximumResponseBytes = 1048576
    )
    if ($PathAndQuery -notmatch '^/api(?:/|\?)' -or $PathAndQuery -match '[\r\n]') {
        throw 'Only a relative official-tools /api request is allowed'
    }
    $uri = [Uri]::new("http://127.0.0.1:$Port$PathAndQuery", [UriKind]::Absolute)
    if ($uri.Scheme -ne 'http' -or $uri.Host -ne '127.0.0.1' -or $uri.Port -ne $Port -or $uri.UserInfo -or $uri.Fragment) {
        throw 'Request must target the fixed 127.0.0.1 HTTP endpoint'
    }
    $handler = [Net.Http.HttpClientHandler]::new()
    $handler.UseProxy = $false
    $handler.AllowAutoRedirect = $false
    $handler.UseCookies = $false
    $client = [Net.Http.HttpClient]::new($handler)
    $client.Timeout = [Threading.Timeout]::InfiniteTimeSpan
    $cancellation = [Threading.CancellationTokenSource]::new($TimeoutMilliseconds)
    $request = [Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Get, $uri)
    $response = $null
    $stream = $null
    $output = [IO.MemoryStream]::new()
    try {
        $response = $client.SendAsync($request, [Net.Http.HttpCompletionOption]::ResponseHeadersRead, $cancellation.Token).GetAwaiter().GetResult()
        $status = [int]$response.StatusCode
        if ($status -ne 200) { throw "Official tools returned HTTP $status; redirects are disabled" }
        if ($null -ne $response.Content.Headers.ContentLength -and $response.Content.Headers.ContentLength -gt $MaximumResponseBytes) {
            throw 'Official tools response exceeded the bounded diagnostic size'
        }
        $stream = $response.Content.ReadAsStreamAsync($cancellation.Token).GetAwaiter().GetResult()
        $buffer = [byte[]]::new(8192)
        while ($true) {
            $allowed = [Math]::Min($buffer.Length, $MaximumResponseBytes - [int]$output.Length + 1)
            $received = $stream.ReadAsync($buffer, 0, $allowed, $cancellation.Token).GetAwaiter().GetResult()
            if ($received -eq 0) { break }
            if ($output.Length + $received -gt $MaximumResponseBytes) { throw 'Official tools response exceeded the bounded diagnostic size' }
            $output.Write($buffer, 0, $received)
        }
        [pscustomobject]@{ StatusCode = $status; Body = [Text.Encoding]::UTF8.GetString($output.ToArray()) }
    }
    catch {
        if ($cancellation.IsCancellationRequested) { throw 'Official tools request exceeded its absolute timeout' }
        throw
    }
    finally {
        if ($stream) { $stream.Dispose() }
        if ($response) { $response.Dispose() }
        $request.Dispose()
        $output.Dispose()
        $client.Dispose()
        $cancellation.Dispose()
    }
}

function Get-MineComeToolsConsoleBinding {
    param([ValidateRange(1,65535)][int]$Port = 1403)
    $binding = Invoke-MineComeToolsRequest -PathAndQuery '/api/System/Console?info' -Port $Port
    if ($binding.Body -notmatch '(?<![A-Za-z0-9_])ExecuteString(?![A-Za-z0-9_])') {
        throw 'Official tools Console ExecuteString binding is not ready'
    }
    $binding
}
