
function AssertAreEqual() {
    param($arg1, $arg2)
    
    if($arg1 -is [array]) {
        AssertAreArraysEqual $arg1 $arg2
        return
    }

    if($arg1 -ne $arg2) {
        throw "Not equal $arg1 != $arg2"
    }
}

function AssertAreArraysEqual() {
    param([array]$arg1, [array]$arg2)

    if($arg1.Length -ne $arg2.Length) {
        throw "Array length mismash"
    }

    for ($i=1;$i -lt $arg1.Length; $i++) {
        AssertAreEqual $arg1[$i] $arg2[$i]
    }
}
