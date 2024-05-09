{
	"subject": {{ toJson .AuthorizationCrt.Subject }},
	"keyUsage": ["keyEncipherment", "digitalSignature"],
	"extKeyUsage": ["clientAuth"]
}
