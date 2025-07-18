
/*Create or Update the SystemStatus */

IF NOT EXISTS (SELECT * FROM SystemStatus WHERE ID = 1)
    INSERT INTO SystemStatus (ID, IsFirstRunCompleted, DomainControllerStatus,DomainControllerLog, WebAppVersion)
    VALUES (1, 0, 0,'', '1.0.0');
ELSE
    UPDATE SystemStatus
    SET 
        WebAppVersion = '1.0.0'
    WHERE ID = 1;

/* Create Settings Entry */
IF NOT EXISTS (SELECT * FROM Settings WHERE ID = 1)
    INSERT INTO Settings (ID, MaxWorkerCount, JobTimeout,JobReview, WorkerVMSize, DcVMSize, DcVMImage, WorkerVMWindowsImage, WorkerVMLinuxImage, DomainFQDN, DomainControllerName, MDEWindowsOnboardingScript, MDELinuxOnboardingScript)
    VALUES (1, 5, 120,0, 'Standard_B2ms', 'Standard_B2ms', 'MicrosoftWindowsServer:WindowsServer:2022-datacenter-g2:latest', 'MicrosoftWindowsDesktop:Windows-11:win11-21h2-ent:latest', 'Canonical:ubuntu-24_04-lts:server:latest', '_DomainFQDN_', 'dc01', '', '');

/* Create System User Info */
IF NOT EXISTS (SELECT * FROM UserInfo WHERE Id = '00000000-0000-0000-0000-000000000000')
    INSERT INTO UserInfo (Id, DisplayName, UserPrincipalName)
    VALUES ('00000000-0000-0000-0000-000000000000', 'SYSTEM', 'SYSTEM');
