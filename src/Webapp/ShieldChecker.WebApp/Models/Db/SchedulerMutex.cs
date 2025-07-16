﻿using Microsoft.EntityFrameworkCore.Migrations.Operations;
using System.Security.Claims;

namespace ShieldChecker.WebApp.Models.Db
{
    
public class SchedulerMutex
    {
        public SchedulerMutex()
        {
            Owner = string.Empty; // Initialize non-nullable property to avoid CS8618
        }

        public int Id { get; set; }
        public string Owner { get; set; }
        public SchedulerType SchedulerType { get; set; } = SchedulerType.Worker;

        public DateTime Start { get; set; }
    }
}
