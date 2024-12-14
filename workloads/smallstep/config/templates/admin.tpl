{
	"subject": {
		"commonName": {{ toJson .Insecure.CR.Subject.CommonName }},
		"organization": "system:masters"
	},
	"keyUsage": ["keyEncipherment", "digitalSignature"],
	"extKeyUsage": ["clientAuth"]
}
