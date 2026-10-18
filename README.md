# WardPulse

See your AI plan capacity, purchased balances and API spend on Android. WardPulse brings
reporting from OpenAI, Anthropic and Cursor into one phone dashboard, with an optional
Wear OS summary, watch face and home-screen widget.

<table width="100%">
  <tr>
    <td width="50%" rowspan="2" align="center">
      <a href="docs/assets/phone-providers-light.png#gh-light-mode-only"><img src="docs/assets/phone-providers-light.png#gh-light-mode-only" width="216" alt="WardPulse phone Providers showing separate plan and reporting connections, four Connected rows and warning count 1 in the light theme."></a>
      <a href="docs/assets/phone-providers-dark.png#gh-dark-mode-only"><img src="docs/assets/phone-providers-dark.png#gh-dark-mode-only" width="216" alt="WardPulse phone Providers showing separate plan and reporting connections, four Connected rows and warning count 1 in the dark theme."></a><br>
      <strong>Phone Providers · Connected rows, warning count 1</strong>
    </td>
    <td width="50%" align="center">
      <a href="docs/assets/wear-glance.png"><img src="docs/assets/wear-glance.png" width="200" alt="WardPulse Watch Glance showing plan capacities, amber !OK and Stale."></a><br>
      <strong>Watch Glance · Stale</strong>
    </td>
  </tr>
  <tr>
    <td width="50%" align="center">
      <a href="docs/assets/wear-watch-face.png"><img src="docs/assets/wear-watch-face.png" width="200" alt="Historical WardPulse watch face showing usage rings and upper complications."></a><br>
      <strong>Historical WardPulse face</strong>
    </td>
  </tr>
</table>

[Read the user guide](https://neuroborus.github.io/ward-pulse/).

## Start using WardPulse

Sign-in and fresh reporting need internet access. The watch face requires Wear OS 5 or later;
the phone can be used on its own. Plan connections are experimental.

- [Getting started](docs/product/user-guide/GETTING_STARTED.md)
- [Connect providers](docs/product/user-guide/PROVIDERS.md)
- [Read the Dashboard](docs/product/user-guide/DASHBOARD.md)
- [Watch and watch face](docs/product/user-guide/WATCH.md)
- [Home widget](docs/product/user-guide/WIDGET.md)
- [Sync and notifications](docs/product/user-guide/SYNC.md)
- [Settings and privacy](docs/product/user-guide/SETTINGS.md)
- [Troubleshooting](docs/product/user-guide/TROUBLESHOOTING.md)

WardPulse stores your credentials encrypted on the phone and uses them directly with their
provider. The watch receives a compact summary without credentials. There is no WardPulse
application server or developer usage telemetry. Read the [privacy policy](docs/product/PRIVACY_POLICY.md).

## License

WardPulse source code and documentation are licensed under [Apache-2.0](LICENSE) unless
otherwise stated. The license does not grant rights to the WardPulse name, logo or other
product branding; see [Trademark rules](TRADEMARKS.md).

Contributing: see the [project documentation for contributors](docs/README.md).
