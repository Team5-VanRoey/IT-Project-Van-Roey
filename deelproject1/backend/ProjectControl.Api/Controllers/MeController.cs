using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Identity.Web;
using Microsoft.Identity.Web.Resource;
using System.Security.Claims;

namespace ProjectControl.Api.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    [Authorize]
    [RequiredScope("access_as_user")]
    public class MeController : ControllerBase
    {
        [HttpGet]
        public IActionResult Get()
        {
            return Ok(new
            {
                Name = User.FindFirstValue("name"),
                ObjectId = User.GetObjectId(),
                TenantId = User.GetTenantId(),
                Roles = User.FindAll(ClaimTypes.Role).Select(c => c.Value),
                Claims = User.Claims.Select(c => new { c.Type, c.Value })
            });
        }
    }
}
