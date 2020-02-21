// --------------------------------------------------------------------------------------------------------------------
// <copyright file="VaultSettings.cs" company="Microsoft">
// </copyright>
// <summary>
//  The ElectricalDatacenterHealthService
// </summary>
// --------------------------------------------------------------------------------------------------------------------

namespace Common.KeyVault
{
    public class VaultSettings
    {
        public string VaultName { get; set; }
        public string VaultUrl => $"https://{VaultName}.vault.windows.net";
    }
}