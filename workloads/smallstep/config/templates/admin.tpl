{
	"subject": {
		"commonName": {{ toJson .Insecure.CR.Subject.CommonName }},
		"extraNames": [{"type":"2.5.4.10", "value": "system:masters"}]
	},
	"keyUsage": ["keyEncipherment", "digitalSignature"],
	"extKeyUsage": ["clientAuth"]
}
