# New Sandbox Routing

## When `gbasf2 ...` is executed
- Normal execution begins
    - Local temporary jdl is made by gbasf2
    - Local files to be used in inputsandbox are recorded in "job" object
- Before job submission, new code modifies job object
    - Gathers inputsandbox files
    - Chooses random TMP-SE to store inputsandbox files as a dataset
    - Uploads input files to SE, marked with timestamp to avoid conflicts
    - Modifies jdl to point to new uploaded files ("LFN:/belle/...")
    - Cleans user data space to get rid of old sandboxes
    - This new job object is submitted to dirac
    - New code: gbasf2/BelleDirac/gbasf2/lib/job/storeSandbox.py
    - Modified code: gbasf2/BelleDIRAC/gbasf2/lib/gbasf2.py
        - gbasf2/BelleDIRAC/Client/controllers/projectCLController.py had import problems so modified slightly

- After submission
    - Sandbox that was just uploaded is deleted from TMP-SE
        - Seems to still work with jobs downloading from above SE
        - If we skip this step the job appears with a `gfal-ls` in the SE
    - Pilot looks like it is downloading sandbox from SE
    - Job runs as normal
