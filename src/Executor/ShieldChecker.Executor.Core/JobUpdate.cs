using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace ShieldChecker.Executor.Core
{
    public class JobUpdate
    {
        public int? Status { get; set; }
        public required string TestOutput {  get; set; }
        public required string ExecutorOutput { get; set; }
    }
}
