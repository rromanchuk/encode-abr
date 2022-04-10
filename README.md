# encode-abr




## Use the SAM CLI to build and test locally

Build your application with the `sam build` command.

```bash
encoder-abr$ sam build --use-container
```

Run functions locally and invoke them with the `sam local invoke` command.

```bash
encoder-abr$ sam local invoke EcodeAbrFunction --event events/sqs.json
```

## Fetch, tail, and filter Lambda function logs


```bash
encoder$ sam logs -n EcodeAbrFunction --stack-name encoder-app -t
```
