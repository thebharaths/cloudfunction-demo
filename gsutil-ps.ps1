# Copyright 2013 Google Inc. All Rights Reserved.

# Override CLOUSDSDK_PYTHON_SITEPACKAGES for the current script only.
$cloudsdk_python_sitepackages = 1

# <cloud-sdk-ps1-preamble>
#
#  CLOUDSDK_ROOT_DIR            (a)  installation root dir
#  CLOUDSDK_PYTHON              (u)  python interpreter path
#  CLOUDSDK_GSUTIL_PYTHON       (u)  python interpreter path for gsutil
#  CLOUDSDK_PYTHON_ARGS         (u)  python interpreter arguments
#  CLOUDSDK_PYTHON_SITEPACKAGES (u)  use python site packages
#
# (a) always defined by the preamble
# (u) user definition overrides preamble


function Restore-Environment([System.Collections.DictionaryEntry[]] $origEnv) {
  # Remove any added variables.
  compare-object $origEnv $(get-childitem Env:) -property Key -passthru |
      where-object { $_.SideIndicator -eq "=>" } |
          foreach-object { remove-item -path ("Env:" + $_.Name); }
  # Revert any changed variables to original values.
  compare-object $origEnv $(get-childitem Env:) -property Value -passthru |
      where-object { $_.SideIndicator -eq "<=" } |
          foreach-object { set-item -path ("Env:" + $_.Name) -value $_.Value }
}

# Save the original environmental variables so we can restore them at the end.
$origEnv = get-childitem Env:

$current_dir = Split-Path $script:MyInvocation.MyCommand.Path
$cloudsdk_root_dir = (Resolve-Path (Join-Path $current_dir '..')).Path
$env:PATH = (Join-Path $cloudsdk_root_dir 'bin\sdk') + ';' + $env:PATH

if (!$cloudsdk_python) {
  $cloudsdk_python = $env:CLOUDSDK_PYTHON
}
if (!$cloudsdk_python) {
  $bundled_python = Join-Path $cloudsdk_root_dir 'platform\bundledpython\python.exe'
  if (Test-Path $bundled_python) {
    $cloudsdk_python = $bundled_python
  } else {
    $cloudsdk_python = 'python.exe'
  }
}

if (!$cloudsdk_python_sitepackages) {
  $cloudsdk_python_sitepackages = $env:CLOUDSDK_PYTHON_SITEPACKAGES
}
if (!$cloudsdk_python_sitepackages) {
  if (!(Test-Path env:\VIRTUAL_ENV)) {
    $cloudsdk_python_sitepackages = ''
  } else {
    $cloudsdk_python_sitepackages = 1
  }
}

if (!$cloudsdk_python_args) {
  $cloudsdk_python_args = $env:CLOUDSDK_PYTHON_ARGS
}
$cloudsdk_python_args_no_s = ''
if ($cloudsdk_python_args) {
  $args_array_no_s = ($cloudsdk_python_args.split(' ') | ? {$_ -cne '-S'})
  if ($args_array_no_s) {
    $cloudsdk_python_args_no_s = [string]::join(' ', $args_array_no_s)
  }
}
if (!$cloudsdk_python_sitepackages) {
  $cloudsdk_python_args = $cloudsdk_python_args_no_s + ' -S'
} else {
  $cloudsdk_python_args = $cloudsdk_python_args_no_s
}

# TODO(b/133246173): Remove this once we want to default to Python 3.
# Allow users to set the Python interpreter used to launch gsutil, falling
# back to the CLOUDSDK_PYTHON interpreter otherwise. In the future, if this
# is not set, we'll try finding (and prefer using) Python 3 before falling
# back to the default Cloud SDK Python.
if (!$cloudsdk_gsutil_python) {
  $cloudsdk_gsutil_python = $cloudsdk_python
}

# Gsutil prefers Python 3 if it is available, which may likely differ from the
# $CLOUDSDK_PYTHON version. We launch gsutil with $CLOUDSDK_GSUTIL_PYTHON; the
# user can set this to any interpreter they like, so we only try to find
# Python 3 for them if they haven't specified the interpreter already.
if (!$cloudsdk_gsutil_python) {
  if ((Get-Command python3 -errorAction SilentlyContinue) -and `
      (python3 -c 'import sys; vi = sys.version_info; print((vi.major, vi.minor) >= (3, 5))') -eq 'True') {
    # Try `python3` first.
    $cloudsdk_gsutil_python = Get-Command python3 | Select-Object -ExpandProperty Definition
  } elseif ((Get-Command python -errorAction SilentlyContinue) -and `
            (python -c 'import sys; vi = sys.version_info; print((vi.major, vi.minor) >= (3, 5))') -eq 'True') {
    # If `python3` isn't found or valid, try `python`.
    $cloudsdk_gsutil_python = Get-Command python | Select-Object -ExpandProperty Definition
  } else {
    # Python 3 doesn't appear to be in the OS path. Use $CLOUDSDK_PYTHON.
    $cloudsdk_gsutil_python = $cloudsdk_python
  }
}

$env:CLOUDSDK_ROOT_DIR = $cloudsdk_root_dir
$env:CLOUDSDK_PYTHON_ARGS = $cloudsdk_python_args
$env:CLOUDSDK_GSUTIL_PYTHON = $cloudsdk_gsutil_python

# </cloud-sdk-ps1-preamble>

# Powershell properly escapes arguments passed by array.
$run_args_array = @() # empty array
if ($cloudsdk_python_args) {
  $run_args_array += $cloudsdk_python_args.split(' ')
}
$run_args_array += (Join-Path $cloudsdk_root_dir 'bin\bootstrapping\gsutil.py')
$run_args_array += $args

if ($MyInvocation.ExpectingInput) {
  $input | & "$cloudsdk_gsutil_python" $run_args_array
} else {
  & "$cloudsdk_gsutil_python" $run_args_array
}

Restore-Environment $origEnv

exit $LastExitCode
