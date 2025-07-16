using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.Linq;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Threading.Tasks;

namespace ShieldChecker.Executor.Core
{
    public enum OperatingSystem
    {
        Windows,
        Linux
    }
    public enum ExecutorSystemType
    {
        Worker,
        DomainController
    }
    public enum ExecutorUserType
    {
        System,
        local_admin,
        domain_admin,
        domain_user
    }
    public class TestDefinition
    {
        public int ID { get; set; }
        public string Name { get; set; } = string.Empty;
        public string ScriptTest { get; set; } = string.Empty;
        public string ScriptPrerequisites { get; set; } = string.Empty;
        public string ScriptCleanup { get; set; } = string.Empty;
        public bool ElevationRequired { get; set; } = true;
        public OperatingSystem OperatingSystem { get; set; }
        public ExecutorSystemType ExecutorSystemType { get; set; }
        public ExecutorUserType ExecutorUserType { get; set; }
        public string? Username { get; set; }
        public string? Password { get; set; }
        public string? Domain { get; set; }
    }
}
